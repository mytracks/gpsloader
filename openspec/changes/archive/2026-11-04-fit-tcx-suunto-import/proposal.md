# Proposal: FIT-, TCX- und Suunto-Import in GPSLoggerKit

## Why

Garmin FIT, TCX und Suunto Ambit SML sind die Dateiformate der Sportuhren und Fahrradcomputer im Gerätekatalog. Die Alt-App las FIT und TCX nur über gpsbabel und Suunto über ein Python-2-Skript (`ambit2gpx.py`), das es auf aktuellen Macs nicht mehr gibt. FIT und TCX sind öffentlich spezifiziert, und das Suunto-Format lässt sich aus Beispieldateien ableiten. Damit folgt dieser Change in der Reihenfolge von `openspec/config.yaml` direkt auf IGC. Durch den Dateimodus der App (`file-conversion`) stehen die Formate dort sofort zur Verfügung.

## What Changes

- **Neues Format `fit` (Garmin FIT, binär)** in GPSLoggerKit, für macOS und iOS:
  - Gelesen werden Dateikopf, Definitions- und Datennachrichten in beiden Byte-Reihenfolgen, komprimierte Zeitstempel, Entwicklerfelder (diese werden übersprungen) und mehrere aneinandergehängte FIT-Dateien.
  - Aus `record`-Nachrichten entstehen Trackpunkte mit Zeit, Position, Höhe und Geschwindigkeit. Timer-Stopps und -Starts teilen den Track in Segmente.
  - Bei Kursdateien bestimmt `course` den Track-Namen, und `course_point` wird zu Wegpunkten.
  - Eine falsche Prüfsumme oder eine abgeschnittene Datei ergibt eine Warnung. Alles, was bis dahin gelesen wurde, bleibt erhalten.
- **Neues Format `tcx` (Garmin Training Center XML)**:
  - Jede `Activity` ergibt einen Track, jedes `Track`-Element darin ein Segment.
  - Jeder `Course` ergibt einen Track mit seinem Namen, und `CoursePoint` wird zu Wegpunkten.
  - Übernommen werden Zeit, Position, Höhe und Geschwindigkeit aus der Erweiterung `TPX`.
- **Neues Format `suunto-sml` (Suunto Ambit, Moveslink/Movescount SML)**:
  - Gelesen werden GPS-Proben mit Position im Bogenmaß, UTC-Zeit, GPS-Geschwindigkeit, Kurs, HDOP und Satellitenzahl.
  - Die Höhe kommt aus der barometrischen Höhe der periodischen Proben, sonst aus der GPS-Höhe.
  - Pausen teilen den Track in Segmente. Jede Datei ergibt einen Track mit dem Dateinamen.
  - Erkannt werden die Dateiendungen `.sml` und `.xml`.
- Alle drei Formate werden am Inhalt erkannt.
- Neue Warnungsarten:
  - falsche Prüfsumme einer ganzen Datei, die trotzdem gelesen wurde;
  - unvollständige Datei.
- Ein gemeinsamer Helfer erkennt das Wurzelelement von XML-Dateien. Ihn nutzen GPX, TCX und Suunto.
- Der Formatkatalog enthält zusätzlich FIT, TCX und Suunto SML. `PROVENANCE.md` nennt die Quellen.

## Capabilities

### New Capabilities

- `fit-import`: Garmin-FIT-Dateien einlesen und daraus Tracks und Wegpunkte bilden.
- `tcx-import`: TCX-Dateien (Aktivitäten und Kurse) einlesen und daraus Tracks und Wegpunkte bilden.
- `suunto-import`: Suunto-Ambit-SML-Dateien einlesen und daraus Tracks bilden.

### Modified Capabilities

- `logger-kit`:
  - Der Formatkatalog enthält zusätzlich `fit`, `tcx` und `suunto-sml`.
  - Die Warnungen umfassen auch eine falsche Datei-Prüfsumme und eine unvollständige Datei.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Garmin FIT Fileformat** und **Canmore G-Porter GP-102+**: Dateimodus, bisher gpsbabel `garmin_fit`.
- **TCX Fileformat**: Dateimodus, bisher gpsbabel `-i gtrnctr -x transform,rte=trk`.
- **Suunto Ambit/Movescout Fileformat (SML)** und **(XML)**:
  - Dateimodus, bisher über `ambit2gpx.py`. Beide Einträge führen dasselbe Skript aus, nur die Dateiendung unterscheidet sich.
  - Laut `config.yaml` entfällt der skriptbasierte Weg und wird hiermit nativ ersetzt.
- Mittelbar sind alle Garmin-, Wahoo-, Polar- und weiteren Geräte abgedeckt, die FIT oder TCX exportieren. Der Katalog führt sie nicht einzeln.
- Nicht betroffen sind die Garmin-Geräte mit LoadMyTracks (Edge 205/305/605/705 u. a.). Sie entfallen laut `config.yaml`.

## Nicht im Umfang

- **Sportdaten:**
  - Gemeint sind Herzfrequenz, Trittfrequenz, Leistung, Temperatur, Kalorien, Runden- und Sitzungszusammenfassungen. GPX 1.1 kann sie ohne Erweiterungen nicht ausgeben, und das Datenmodell hat keine Felder dafür.
  - Das folgt dem IGC-Change, der ebenfalls nur Positionen übernimmt.
- **Weitere FIT-Dateiarten:** Workouts, Einstellungen, Monitoring, Segmente und Wegpunktdateien (`location`) werden gelesen, enthalten aber keine Trackpunkte und ergeben deshalb „keine verwertbaren Daten“.
- **TCX-Inhalte:** `MultiSportSession`, `Workouts`, `Folders` und die TCX-Version 1 werden nicht ausgewertet.
- **Andere Suunto-Formate:**
  - Gemeint sind Moveslink-2-Rohdateien ohne SML-Wurzelelement, Suunto-FIT-Exporte (diese laufen über `fit`) und die JSON-Formate von Suunto App und Movescount.
  - Ob Moveslink-Rohdateien vorkommen, klärt die manuelle Prüfung. Bei Bedarf folgt ein eigener Change.
- **FIT-, TCX- und SML-Ausgabe:** Das Paket schreibt nur GPX.
- **Komprimierte Dateien** wie `.fit.gz` aus Garmin-Connect-Exporten.
- **Echte Aufzeichnungen als Fixtures:** Entschieden am 2026-11-03: Das Paket bekommt nur synthetische Fixtures. Echte Dateien des Entwicklers dienen nur der manuellen Prüfung.

## Impact

- Neue Dateien in `Packages/GPSLoggerKit/Sources/GPSLoggerKit/Formats/FIT/`, `Formats/TCX/` und `Formats/Suunto/`, dazu ein gemeinsamer XML-Helfer.
- Tests mit synthetischen Fixtures, für FIT mit einem kleinen Test-Encoder.
- `FileFormatID.fit`, `.tcx` und `.suuntoSML` werden in `FileFormats.all` eingetragen.
- `ImportWarningKind` bekommt zwei neue Fälle mit Lokalisierung (Deutsch, Englisch).
- `PROVENANCE.md` und das README des Pakets werden ergänzt.
- Die App braucht keine Änderung, denn der Dateimodus übernimmt neue Formate automatisch. Nur die Formatliste im Bereich „Dateien“ wird länger.
- Neue Abhängigkeiten gibt es nicht.
