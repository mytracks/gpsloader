# Design: FIT-, TCX- und Suunto-Import

## Context

GPSLoggerKit hat den Formatvertrag `FileFormat` (`matches(prefix:)`, `read(_:)`), die Erkennung über `FileFormats.detect`, den `WarningCollector`, `CancellationCheck` (alle 4096 Einheiten) und die Formate NMEA, GPX und IGC. Der GPX-Leser arbeitet mit `XMLParser`, das als Stream läuft und auf macOS und iOS vorhanden ist. Er erkennt das Wurzelelement selbst, in `GPXFileFormat.matches`. Zeitangaben im Format XML-`dateTime` liest `ISO8601.date` in `Processing/UTCTime.swift`.

So arbeitete die Alt-App:
- **Katalog:** `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`, Einträge ca. Zeile 1110–1210, zusammengefasst in `docs/legacy-device-catalog.md`, Zeilen 90–107.
- **FIT:** gpsbabel `garmin_fit`.
- **TCX:** gpsbabel `-i gtrnctr -x transform,rte=trk`. gpsbabel liest Kurse als Routen und machte daraus Tracks.
- **Suunto:** ein Shell-Kommando, das `myTracks/Source/Resources/suuntoconvert/ambit2gpx.py` aufruft, für `.sml` und `.xml` mit demselben Skript.
- **`fit2tcx`:** Perl mit `Garmin/FIT.pm` war im Katalog nicht mehr in Gebrauch.

Eigenen Code für diese Formate hat myTracks nicht.

## Goals / Non-Goals

**Goals:**
- Drei Formate auf macOS und iOS ohne gpsbabel, Python und Perl. Erkennung, Warnungen und Abbruch funktionieren wie bei den vorhandenen Formaten.
- Ein FIT-Decoder ohne fremde Bibliothek, geprüft mit einem Test-Encoder.
- Alle Fixtures sind synthetisch (Entscheidung des Entwicklers vom 2026-11-03).

**Non-Goals:**
- Sportdaten, weitere FIT-Dateiarten, Ausgabe in diesen Formaten (siehe Proposal, „Nicht im Umfang“).
- Ein vollständiger Abdruck des FIT-Profils. Nur die Nachrichten und Felder aus D3 werden ausgewertet.

## Decisions

### D1 Quellen und Clean-Room

- **FIT:**
  - Grundlage sind die öffentliche „FIT Protocol“-Beschreibung von Garmin (developer.garmin.com/fit/protocol, mit Dateikopf, Record-Header, Definitionen, Basistypen, Ungültigkeitswerten, komprimiertem Zeitstempel und CRC-Algorithmus) und das FIT-Profil des FIT SDK (`Profile.xlsx`) für Nachrichten- und Feldnummern, Skalierung und Offset.
  - Der Quelltext des FIT SDK wird nicht übernommen.
  - gpsbabel `garmin_fit` sowie `fit2tcx` und `Garmin/FIT.pm` (Perl, Lizenz unklar) werden nicht gelesen.
- **TCX:** das öffentliche Schema `TrainingCenterDatabasev2.xsd` und `ActivityExtensionv2.xsd` von Garmin. gpsbabels `gtrnctr` wird nicht gelesen.
- **Suunto SML:**
  - Es gibt keine öffentliche Spezifikation. Der Aufbau wird als Black-Box aus der Beispieldatei `myTracks/Source/Resources/suuntoconvert/ambit.xml` (Suunto Ambit, 2014) abgeleitet. Ausgewertet wurden nur Elementnamen, Probentypen und Einheiten. Werte aus der Datei, insbesondere Positionen, kommen weder in Specs noch in Tests vor.
  - Das Ergebnis:
    - Wurzel `sml` im Namensraum `http://www.suunto.com/schemas/sml`, darunter `DeviceLog/Samples/Sample`.
    - `Latitude` und `Longitude` sowie `GPSHeading` stehen im Bogenmaß.
    - `UTC` ist ein ISO-8601-Wert mit `Z`.
    - Die Probentypen sind `periodic` (mit `Altitude`), `gps-base` und `gps-small`.
    - Pausen stehen in `Events/Pause/State`.
  - `ambit2gpx.py` stammt aus dem Google-Code-Projekt `ambit2gpx`, dessen Lizenz unbekannt ist, möglicherweise GPL. Der Entwickler hat es zum Lesen freigegeben, aber nach den Clean-Room-Regeln in `config.yaml` bleibt es ungelesen, solange die Lizenz nicht geklärt ist.
  - Die Beispieldatei wird nicht ins Paket übernommen.
- `PROVENANCE.md` erhält die Abschnitte `fit`, `tcx` und `suunto-sml`. Der vorhandene Provenance-Test verlangt das für jedes Format im Katalog.

### D2 Gemeinsamer XML-Helfer

`GPXFileFormat.matches` wird zu einem internen Helfer `XMLSniffer.rootElementLocalName(in:)` (`Formats/XMLSniffer.swift`). Er überspringt die XML-Deklaration, Kommentare und DOCTYPE und liefert den lokalen Namen des ersten Elements. Die Erkennung nutzt ihn so:
- GPX vergleicht mit `gpx`.
- TCX vergleicht mit `TrainingCenterDatabase`.
- Suunto vergleicht mit `sml`.

Die drei Wurzelnamen sind verschieden, deshalb kann die Erkennung nicht doppeldeutig werden, auch nicht bei der gemeinsamen Endung `.xml`.

Für das Lesen bekommen TCX und Suunto je einen eigenen `XMLParserDelegate` nach dem Muster des GPX-Lesers:
- `shouldProcessNamespaces = true`.
- Externe Entitäten sind abgeschaltet.
- Text wird gesammelt, und die Auswertung geschieht beim Ende des Elements.
- `CancellationCheck` pro Element, bei Abbruch `abortParsing()` und dann `CancellationError`.

Verglichen wird nur der lokale Elementname. So funktionieren auch Dateien mit anderem Präfix oder mit fehlendem Namensraum.

Alternative: ein gemeinsamer generischer Pfad-Parser für alle XML-Formate. Verworfen, weil die drei Formate wenig Struktur teilen und eigene Delegates leichter zu lesen sind.

### D3 FIT-Decoder

`FITFileFormat` (öffentlich) und intern `FITDecoder`, der auf `Data` mit einem Byte-Offset arbeitet. Er kopiert keine Teilbereiche.

**Kopf:**
- Byte 0 gibt die Kopflänge an (12 oder 14). Byte 4–7 enthält die Länge des Datenbereichs (UInt32 LE), Byte 8–11 die Kennung `.FIT`.
- Bei 14 Byte folgt in Byte 12–13 die CRC des Kopfs. Der Wert 0 bedeutet „nicht gesetzt“.
- Ist der Kopf ungültig, wirft der Decoder `GPSLoggerError(.malformed(line: nil))`. `line` bleibt nil, Details enthält den Byte-Offset.

**Record-Header:**
- Bit 7 = 1 heißt komprimierter Zeitstempel: Bits 5–6 geben die lokale Art an, Bits 0–4 den Versatz.
- Sonst gilt Bit 6 = Definition, Bit 5 = Entwicklerdaten (nur in Definitionen) und Bits 0–3 die lokale Art.

**Definition:**
- Byte 1 gibt die Architektur an (0 = LE, 1 = BE). Byte 2–3 enthält die globale Nachrichtennummer, Byte 4 die Anzahl der Felder.
- Je Feld folgen drei Byte: Nummer, Größe und Basistyp. Bei gesetztem Entwicklerbit kommen eine Anzahl und je drei Byte für Entwicklerfelder dazu, die nur zur Länge zählen.
- Die Definitionen liegen in einer Tabelle mit 16 Einträgen. Sie wird für jede verkettete Datei zurückgesetzt.

**Datennachricht:**
- Nur die Felder aus der Tabelle unten werden dekodiert, abhängig von der globalen Nummer. Alle anderen werden über ihre Größe übersprungen.
- Ein Feld gilt als fehlend, wenn sein Wert der Ungültigkeitswert des Basistyps ist (0xFF, 0x7F, 0xFFFF, 0x7FFF, 0xFFFFFFFF oder 0x7FFFFFFF, bei z-Typen 0) oder wenn seine Größe nicht zum Basistyp passt.

**Zeit:**
- Feld 253 (`timestamp`) gilt für alle Nachrichten. Ein UInt32 zählt die Sekunden ab dem 31.12.1989, 00:00 UTC, also Unix-Zeit + 631065600.
- Werte unter 0x10000000 sind relative Gerätezeit. Sie ergeben keine Zeit und die Warnung `missingDate`.
- Komprimiert: Die neue Zeit ist der letzte volle Zeitstempel mit den unteren 5 Bit ersetzt. Ist der Versatz kleiner als die unteren 5 Bit des letzten Werts, kommen 32 dazu.

**Ausgewertete Nachrichten (FIT-Profil):**

| Nachricht (global) | Feld (Nummer, Typ, Skalierung) |
|---|---|
| `record` (20) | `position_lat` 0 sint32, `position_long` 1 sint32 (Semicircles); `altitude` 2 uint16 /5 −500; `speed` 6 uint16 /1000; `enhanced_speed` 73 uint32 /1000; `enhanced_altitude` 78 uint32 /5 −500; `timestamp` 253 |
| `event` (21) | `event` 0 enum (`timer` = 0); `event_type` 1 enum (`start` = 0, `stop` = 1, `stop_all` = 4) |
| `course` (31) | `name` 5 string (UTF-8, nullterminiert) |
| `course_point` (32) | `timestamp` 1; `position_lat` 2, `position_long` 3; `name` 6 string |

**Segmente:**
- `timer`/`stop` und `timer`/`stop_all` schließen das laufende Segment.
- Der nächste Punkt öffnet ein neues Segment, unabhängig davon, ob vorher ein `start` kam. Manche Geräte schreiben den Start nicht.
- `lap` und `session` werden nicht ausgewertet, ihre Grenzen teilen also keine Segmente.

**Prüfsumme:**
- CRC-16 nach dem Algorithmus der FIT-Protokollbeschreibung (Tabelle mit 16 Einträgen, entspricht CRC-16/ARC), gebildet über Kopf und Daten.
- Weicht die Kopf- oder Datei-CRC ab, gibt es eine Warnung `fileChecksumMismatch` je Datei. Dekodiert wird trotzdem.

**Ende und Verkettung:**
- Nach Datenbereich und CRC beginnt eine weitere FIT-Datei, wenn mindestens 12 Byte übrig sind und der Kopf gültig ist.
- Übrige Bytes, die keinen gültigen Kopf ergeben, werden ignoriert.

**Beschädigt:**
- Ist der Datenbereich kürzer als angegeben, reicht eine Nachricht über das Ende hinaus oder fehlt die Definition einer lokalen Art, endet das Dekodieren dieser Datei.
- Das Ergebnis enthält dann die Punkte bis dahin, dazu die Warnung `truncatedFile`, bei fehlender Definition `malformedRecord` mit dem Byte-Offset.

Der Track heißt wie der Name aus `course`, sonst wie der Dateiname ohne Endung (wie bei IGC).

Alternative: das Swift-SDK von Garmin als Abhängigkeit. Verworfen, weil GPSLoggerKit keine Abhängigkeiten hat, das SDK eine eigene Lizenz mitbringt und nur ein Bruchteil davon gebraucht wird.

### D4 TCX-Leser

`TCXFileFormat` und intern `TCXParserHandler`. Der Zustand ist ein Kontext-Stapel der lokalen Elementnamen.

- `Activity` beginnt einen Track ohne Namen. `Course` beginnt einen Track, dessen Name aus dem direkten Kind `Name` kommt.
- `Track` beginnt ein Segment, `Trackpoint` einen Punkt-Puffer. Beim Ende von `Trackpoint` wird der Punkt übernommen, wenn eine Position vorhanden ist.
- `Speed` zählt nur unterhalb von `Extensions`/`TPX`. `AltitudeMeters`, `Time`, `LatitudeDegrees` und `LongitudeDegrees` zählen nur innerhalb des aktuellen `Trackpoint` bzw. `CoursePoint`.
- `CoursePoint` wird ein Wegpunkt mit `Name`, `Time`, Position, `AltitudeMeters` und `Notes`.
- Alle anderen Teilbäume, darunter `MultiSportSession`, `Workouts`, `Folders`, `Author`, `Creator` und unbekannte Erweiterungen, werden ohne Auswertung übergangen.
- Zahlen werden mit `Double(String)` gelesen, das unabhängig von der Locale ist.
- Die Warnungen `invalidCoordinate`, `malformedRecord` und `missingDate` zählen mit der Zeilennummer des Parsers.

### D5 Suunto-Leser

`SuuntoSMLFileFormat` (Kennung `suunto-sml`, Endungen `sml`, `xml`) und intern `SuuntoParserHandler`.

- Jede `Sample` wird als Wörterbuch ihrer direkten Kindelemente gesammelt (lokaler Name → Text). `Events/Pause/State` wird gesondert gemerkt.
- **Periodische Probe mit `Altitude`:** Höhe und `UTC` werden gemerkt.
- **Probe mit `Latitude` und `Longitude`:** Daraus wird ein Punkt:
  - Bogenmaß × 180/π.
  - `|lat| ≤ π/2` und `|lon| ≤ π`, sonst die Warnung `invalidCoordinate`.
  - Die Höhe richtet sich nach der Regel der Spec. Liegt die gemerkte Höhe höchstens 60 s zurück, gilt sie, sonst `GPSAltitude`.
  - Der Kurs wird in Grad auf 0 bis 360 normalisiert.
- **`Pause`:** `True` schließt das Segment, `False` erlaubt ein neues. Leere Segmente werden am Ende entfernt.
- **Begründung der Höhenregel:** Die Ambit misst die Höhe barometrisch, und im Ein-Sekunden-Modus enthalten die meisten GPS-Proben (`gps-small`) keine `GPSAltitude`. Nur mit GPS-Höhe hätten fast alle Punkte keine Höhe. Ein fester Vorrang der barometrischen Höhe vermeidet Sprünge zwischen beiden Quellen.
- **Alternative:** nur `GPSAltitude`. Verworfen, aus dem genannten Grund.

### D6 Warnungen

`ImportWarningKind` bekommt `fileChecksumMismatch` und `truncatedFile`. Diese Meldungen nennen nur die Datei und keine Anzahl, denn sie gelten pro Datei. `ImportWarning.message()` setzt bei ihnen nur den Dateinamen ein. Der vorhandene Pfad `String(format:, count, fileName)` bleibt für die zählenden Arten.

Lokalisierung:

| Schlüssel | Deutsch | Englisch |
|---|---|---|
| `warning.fileChecksumMismatch` | „Die Prüfsumme von „%@“ stimmt nicht. Die Datei wurde trotzdem gelesen.“ | „The checksum of “%@” is wrong. The file was read anyway.“ |
| `warning.truncatedFile` | „„%@“ ist unvollständig. Nur der lesbare Anfang wurde übernommen.“ | „“%@” is incomplete. Only the readable beginning was used.“ |

Die genaue Wortwahl legt die Umsetzung fest.

### D7 Nebenläufigkeit und Abbruch

Wie bei den übrigen Formaten:
- `read` ist synchron und wird von `FileFormats.read` außerhalb des Main Actors aufgerufen.
- Alle Typen sind `Sendable`-Werttypen, und die Parser-Delegates leben nur innerhalb eines `read`-Aufrufs.
- FIT prüft `CancellationCheck` pro Nachricht, TCX und Suunto pro Element.
- Nach einem Abbruch kommt `CancellationError` ohne Teilergebnis.
- Ein Zeitlimit ist nicht nötig, weil Dateien endlich sind.

### D8 Tests und Fixtures

- **FIT:** Ein Test-Encoder `FITTestFile` im Testziel schreibt Kopf, Definitionen (LE/BE, mit Entwicklerfeldern), Datennachrichten, komprimierte Zeitstempel und CRC. Damit lassen sich alle Spec-Szenarien gezielt erzeugen, auch abgeschnittene Dateien, falsche CRC und verkettete Dateien.
  - Zusätzlich gibt es zwei kleine Fixture-Dateien, `activity.fit` und `course.fit`. Ein Testlauf hat sie mit dem Encoder erzeugt, und sie liegen als Binärdatei unter `Fixtures/`. So bleibt die Erkennung über echte Dateien getestet.
- **TCX und SML:** handgeschriebene Fixtures mit erfundenen Koordinaten nach dem XSD bzw. nach dem Aufbau aus D1.
- **Abbruch:** je eine große synthetische Datei im Test (FIT etwa 1 Mio. Nachrichten, TCX/SML etwa 50 MB), Ende in weniger als einer Sekunde.

## Risks / Trade-offs

- [FIT-Profilnummern aus dem Gedächtnis statt aus `Profile.xlsx`] → Die Umsetzung prüft jede Nummer der Tabelle in D3 gegen das aktuelle FIT-Profil von developer.garmin.com. Die manuelle Prüfung mit echten Dateien (Aufgabe 6.3) deckt Abweichungen auf.
- [Der Test-Encoder teilt Annahmen mit dem Decoder, dieselben Fehler bleiben unbemerkt] → Echte FIT-Dateien des Entwicklers werden in der manuellen Prüfung mit gpsbabel 1.7.0 (`garmin_fit`) verglichen: Punktanzahl, erste und letzte Position, Zeitspanne.
- [Das SML-Format ist nur aus einer einzigen Beispieldatei abgeleitet; andere Firmware oder Modelle wie Ambit2/3 können Felder anders benennen] → Der Leser ist tolerant: Unbekannte Elemente stören nicht, und Punkte entstehen allein aus `Latitude`/`Longitude`. Weitere Beispieldateien kommen über die manuelle Prüfung.
- [Moveslink-Rohdateien ohne `sml`-Wurzel werden nicht erkannt] → Sie erscheinen im Dateimodus als „nicht unterstützt“. Mit einer Beispieldatei folgt bei Bedarf ein eigener Change.
- [Mehrere Gigabyte große FIT-Dateien] → Die Daten sind speichergemappt (`FileInput.load`), und der Decoder liest ohne Kopien.

## Migration Plan

Keine. Neue Formate kommen dazu, vorhandene Kennungen und APIs bleiben unverändert. Das Herauslösen des GPX-Wurzel-Erkenners (D2) ist intern.
