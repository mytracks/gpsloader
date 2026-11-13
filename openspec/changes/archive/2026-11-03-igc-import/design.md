# Design: IGC-Import

## Context

GPSLoggerKit hat seit `gpsloggerkit-foundation` einen Formatvertrag (`FileFormat`), Formaterkennung, Warnungen, Abbruch und Nachbearbeitung, dazu die Formate NMEA und GPX. IGC kommt als drittes Textformat hinzu. In der Alt-App lief IGC ausschließlich über gpsbabel (`gpslogger.plist`, Eintrag „IGC Fileformat“, siehe `docs/legacy-device-catalog.md` Zeile 104 und `docs/legacy-analysis.md` Abschnitt 7). Eigenen IGC-Code hatte myTracks nicht, deshalb gibt es unter `input/mytracks4mac/` nichts zu übernehmen.

IGC-Dateien sind ASCII-Text. Jede Zeile ist ein Datensatz, dessen erstes Zeichen den Typ angibt. Für die Aufzeichnung zählen nur drei Typen: B (Positionsfix), I (Aufbau der B-Erweiterungen) und `HFDTE` (Datum).

## Goals / Non-Goals

**Goals:**
- IGC-Dateien auf macOS und iOS ohne gpsbabel lesen, mit derselben Erkennung, denselben Warnungen und demselben Abbruch wie NMEA und GPX.
- Ausschließlich die öffentliche FAI-Spezifikation als Quelle (Clean-Room).
- Gemeinsame Bausteine von NMEA und IGC (Zeilen lesen, Datum aus Tagen und Uhrzeit) nur einmal im Paket.

**Non-Goals:**
- C-Records, G-Signaturprüfung, E/F/K/L-Records, IGC-Ausgabe (siehe Proposal, „Nicht im Umfang“).
- Auswertung weiterer B-Erweiterungen als `SIU`.

## Decisions

### D1 Quelle und Clean-Room

Grundlage ist die „Technical Specification for IGC-approved GNSS Flight Recorders“ der FAI/IGC, Anhang A (Datenformat). Sie ist öffentlich auf fai.org abrufbar. gpsbabels `igc.cc` wird nicht gelesen. `PROVENANCE.md` erhält einen Abschnitt `## \`igc\`` mit Titel und Ausgabestand der Spezifikation; der vorhandene Provenance-Test verlangt das ohnehin für jedes Format im Katalog.

### D2 Gemeinsame Zeilen- und Datumsbausteine

`NMEAFileFormat.forEachLine(in:_:)` liest bereits byte-basiert mit LF, CR und CRLF und liefert Zeilennummer und Text. Diese Funktion wandert unverändert in einen internen Helfer `TextLines` (`Formats/TextLines.swift`), den NMEA und IGC nutzen. Ebenso wandern `NMEASentence.date(ddmmyy:)` (Jahre 1980–2079) und `NMEAFileReader.date(days:timeOfDay:)` nach `Processing/UTCTime.swift`. Das ist reine Verschiebung; die NMEA-Tests sichern ab, dass sich nichts ändert.

Alternative: IGC mit eigener Zeilenlogik. Verworfen, weil doppelter Code mit denselben Randfällen (abgeschnittene letzte Zeile, gemischte Zeilenenden).

### D3 Parser

`IGCFileFormat` (öffentlich, `Formats/IGC/IGCFileFormat.swift`) und ein interner `IGCFileReader` pro Datei:

- Zustand: Datum in Tagen (optional), Zeit des letzten B-Records, Tageszähler, Erweiterungstabelle aus dem I-Record, Punkte, `WarningCollector`.
- B-Records werden über feste Byte-Positionen auf dem UTF-8-Puffer der Zeile gelesen, nicht über `String.Index`. Ziffern werden einzeln geprüft; ein Fehler macht den Datensatz ungültig (`malformedRecord`), eine Position außerhalb des gültigen Bereichs oder Minuten ≥ 60 ergibt `invalidCoordinate`.
- Positionen: Breite `DD + MMmmm / 60000`, Länge `DDD + MMmmm / 60000`, Vorzeichen aus Hemisphäre.
- Höhen: fünf Zeichen, erstes Zeichen darf `-` sein. Regel für die Höhe wie in der Spec (GNSS bei `A` und ≠ 0, sonst Druck ≠ 0, sonst keine).
- I-Record: `I` + zweistellige Anzahl + je 7 Zeichen (Start, Ende, Kürzel). Positionen sind 1-basiert wie in der Spezifikation. Ein ungültiger I-Record wird als `malformedRecord` gezählt und ignoriert.
- `HFDTE`: Nach `HFDTE` folgt entweder direkt `ddmmyy` oder `DATE:ddmmyy` mit optionalem `,nn`. Gelesen wird der erste sechsstellige Ziffernblock nach `HFDTE` bzw. nach dem Doppelpunkt.
- Mitternacht: Ist die Zeit kleiner als die des vorherigen gültigen B-Records, wird der Tageszähler erhöht. Ein Rückwärtssprung um wenige Sekunden würde also einen Tag addieren; die Spezifikation verlangt aufsteigende Zeiten, deshalb wird das bewusst nicht abgefangen.
- Kein Datum: Punkte ohne Zeit, eine `missingDate`-Warnung mit der Anzahl (wie bei NMEA).
- Ergebnis: ein `Track(name: <Dateiname ohne Endung>, segments: [eins])`, nur wenn er Punkte hat.

### D4 Erkennung

`matches(prefix:)`: erste nicht leere Zeile beginnt mit `A` und drei Zeichen aus `A–Z`/`0–9`, und im Prefix (4096 Bytes) beginnt eine weitere Zeile mit `H` oder `B`. Ein A-Record allein reicht nicht, weil viele Textdateien mit „A“ beginnen. NMEA-Dateien beginnen mit `$`, GPX mit `<`; die Formate überschneiden sich also nicht. Endungen: `igc`.

### D5 Nebenläufigkeit und Abbruch

Wie bei NMEA: `IGCFileFormat` ist ein `Sendable`-Wert ohne Zustand, `read` ist synchron und läuft über die vorhandene async-Hülle von `FileFormats` außerhalb des Main Actors. Der Leser ruft `CancellationCheck.tick()` pro Zeile auf (die Prüfung selbst greift alle 4096 Aufrufe) und wirft `CancellationError`. Es gibt keine gemeinsame veränderliche Instanz; jeder `read`-Aufruf baut seinen eigenen `IGCFileReader`. Timeouts sind für Dateien nicht nötig.

### D6 Track pro Datei

Eine IGC-Datei ist genau ein Flug. Anders als bei NMEA (ein Track, ein Segment pro Datei) bekommt deshalb jede Datei einen eigenen Track, benannt nach der Datei. So bleiben mehrere Flüge eines Tages in der GPX-Datei getrennt.

## Risks / Trade-offs

- [Ältere oder fehlerhafte Rekorder weichen von der Spezifikation ab, etwa durch fehlenden A-Record] → Lesen verlangt keinen A-Record; nur die Erkennung tut es. Mit erzwungenem Format lassen sich solche Dateien trotzdem lesen.
- [Keine echten Beispieldateien im Repository] → Synthetische Fixtures nach der Spezifikation; ein manueller Abgleich mit echten Dateien und gpsbabel 1.7.0 ist als Task vorgesehen.
- [Druckhöhe statt GNSS-Höhe kann um einige Dutzend Meter abweichen] → Nur Rückfall, wenn keine GNSS-Höhe vorhanden ist; so dokumentiert.

## Migration Plan

Nicht nötig: neues Format, keine Änderung an bestehendem API. Die Verschiebung aus D2 ist intern.

## Open Questions

Keine.
