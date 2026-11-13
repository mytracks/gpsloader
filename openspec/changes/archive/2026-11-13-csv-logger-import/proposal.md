# Proposal: CSV-Logger-Dateien in GPSLoggerKit (Columbus V-900, iBlue 747)

## Why

Mehrere Logger der Alt-App schreiben ihre Aufzeichnungen als CSV-Dateien auf eine Speicherkarte oder exportieren sie über ihre PC-Software als CSV. Der Dateimodus kann sie bisher nicht lesen, weil er bewusst kein gpsbabel nutzt. Laut `openspec/config.yaml` sind die CSV-Logger die nächste Familie mit offen beschreibbarem Format nach IGC, FIT/TCX/Suunto und KML. Beide Formate sind einfache Textformate. Ihre Spalten nennt die Datei selbst in der Kopfzeile, deshalb lassen sie sich ohne fremden Quelltext umsetzen.

## What Changes

- **Neues Format `v900` (Columbus V-900 und Visiontac VGPS-900, Endung `.csv`)** in GPSLoggerKit, für macOS und iOS:
  - Gelesen wird der einfache Modus (Spalten bis `HEADING` und `VOX`) und der professionelle Modus (zusätzlich `FIX MODE`, `VALID`, `PDOP`, `HDOP`, `VDOP`).
  - Felder mit Füllbytes (NUL) oder Leerzeichen werden getrimmt.
  - Datum `JJMMTT` und Zeit `hhmmss` gelten als UTC.
  - Jede Zeile ergibt einen Trackpunkt. Zeilen mit POI-Markierung (`C`, `D`) oder Sprachaufnahme (`V`) ergeben zusätzlich einen Wegpunkt. Bei Sprachaufnahmen heißt er wie die WAV-Datei.
  - Jede Datei ergibt einen Track, der nach der Datei heißt.
- **Neues Format `iblue-csv` (CSV-Export der iBlue-747/757-Logger, Endung `.csv`)** in GPSLoggerKit, für macOS und iOS:
  - Die Spalten werden über die Kopfzeile zugeordnet, die Reihenfolge ist also beliebig, und unbekannte Spalten werden übergangen.
  - Pflicht sind `DATE`, `TIME`, `LATITUDE`, `N/S`, `LONGITUDE` und `E/W`. Gelesen werden außerdem `VALID`, `HEIGHT`, `SPEED`, `HEADING`, `PDOP`, `HDOP`, `VDOP` und `NSAT`.
  - Als Datum gilt `JJJJ/MM/TT` (iBlue 747) oder `TT/MM/JJJJ` (iBlue 757), als Zeit `hh:mm:ss`, wahlweise mit Bruchteilen. Beide gelten als UTC.
  - Alle Zeilen einer Datei ergeben einen Track, der nach der Datei heißt.
- Beide Formate werden am Inhalt erkannt, also an der Kopfzeile bzw. am Aufbau der ersten Zeilen. Die gemeinsame Endung `.csv` entscheidet nicht.
- Der Formatkatalog enthält zusätzlich `v900` und `iblue-csv`. `PROVENANCE.md` nennt die Quellen.

## Zuordnung der Familie (Regel aus `openspec/config.yaml`)

- **Vorschlag: Clean-Room in GPSLoggerKit (MIT).** Es wird kein GPL-Quelltext gelesen.
- **Grundlagen:**
  - die öffentliche Bedienungsanleitung der Columbus V-900, die die aufgezeichneten Werte aufzählt;
  - die Kopfzeilen, die die Dateien selbst mitbringen;
  - Black-Box-Beobachtung des gpsbabel-1.7.0-Binaries: Es liest synthetische V-900-Dateien (`-i v900`) und schreibt iBlue-CSV aus einer synthetischen GPX-Datei (`-o iblue747`, `-o iblue757`).
- **Entscheidung des Entwicklers ausstehend:** Der Entwickler hat am 2026-11-13 beauftragt, „so viel wie möglich“ umzusetzen, und war für eine Rückfrage nicht erreichbar.
  - Clean-Room ist die einzige Wahl, die nichts festlegt: Solange kein GPL-Quelltext gelesen ist, kann die Familie später immer noch nach GPSLoggerKitGPL wechseln.
  - Der Entwickler bestätigt die Zuordnung bei der Durchsicht, siehe Task 6.3. **Bestätigt am 2026-11-13.**

## Capabilities

### New Capabilities

- `csv-logger-import`: CSV-Dateien der Logger Columbus V-900/Visiontac VGPS-900 und iBlue 747/757 einlesen und daraus Tracks und Wegpunkte bilden.

### Modified Capabilities

- `logger-kit`: Der Formatkatalog enthält zusätzlich `v900` und `iblue-csv`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Datei-Geräte mit Treiber `v900`:** „Columbus V-900 (using memory card reader)“ und „Visiontac VGPS-900“.
- **iBlue 747 und weitere MTK-Logger:**
  - Ihr Speicher wird in myTracks über den gpsbabel-Treiber `mtk` ausgelesen (Familie MTK, eigener Change).
  - Die CSV-Datei dieses Changes entsteht nicht am Logger, sondern in der PC-Software des Herstellers. Der Gerätekatalog führt sie nicht.
  - `openspec/config.yaml` nennt „iBlue747-CSV“ im nativen Umfang.
- **Medion GoPAL (Treiber `gopal`):** gehört zur Familie, ist aber nicht im Umfang, siehe unten.

## Nicht im Umfang

- **Medion GoPal (`.trk`):** Es gibt weder Beispieldateien noch eine öffentliche Beschreibung. Das gpsbabel-Binary schreibt aus einer synthetischen GPX-Datei eine leere Datei, eine Black-Box-Beobachtung ist so also nicht möglich. GoPal kommt in einen eigenen Change, sobald Beispieldateien vorliegen.
- **Ortszeit:** Die Zeiten beider Formate gelten als UTC, wie bei gpsbabel 1.7.0 beobachtet. Logger, deren Firmware Ortszeit schreibt, bekommen keine Option zur Zeitverschiebung. Zeigt der Hardware-Test (Task 6.2) Ortszeiten, folgt ein eigener Change.
- **Sprachaufnahmen:** Die WAV-Dateien werden nicht gelesen und nicht in die GPX-Datei verlinkt. Der Wegpunkt trägt nur den Dateinamen.
- **Weitere iBlue-Werte:** `RCR` (Anlass der Aufzeichnung), `DSTA`, `DAGE`, Satelliteninformationen und `DISTANCE` werden nicht übernommen. Eine Aufzeichnung per Taste (`RCR` = `B`) ergibt keinen Wegpunkt, wie bei gpsbabel.
- **Einheiten außer Meter und km/h:** Spaltenköpfe mit anderen Einheiten sind nicht beobachtet und werden nicht ausgewertet.
- **Allgemeiner CSV-Import:** Es gibt keine frei konfigurierbare Spaltenzuordnung wie bei gpsbabels `xcsv`.
- **Echte Dateien als Fixtures:** Es gibt nur synthetische Fixtures mit erfundenen Koordinaten.

## Impact

- Neue Dateien in `Packages/GPSLoggerKit/Sources/GPSLoggerKit/Formats/CSV/`: ein gemeinsamer Zeilen- und Feldleser sowie je ein Formatleser.
- `FileFormatID.v900` und `FileFormatID.iblueCSV` werden in `FileFormats.all` eingetragen, die Formatnamen bekommen eine Lokalisierung (Deutsch, Englisch).
- Tests mit synthetischen Fixtures, dazu eine Black-Box-Gegenprüfung mit dem gpsbabel-Binary.
- `PROVENANCE.md`, das README des Pakets, das README des Repositorys und `openspec/config.yaml` werden ergänzt. In `config.yaml` kommt die Zuordnung der Familie dazu, mit dem Vermerk „Bestätigung ausstehend“.
- Die App braucht keine Änderung, denn der Dateimodus übernimmt neue Formate automatisch. Das Hauptfenster listet dann neun Formate.
- Neue Paketabhängigkeiten gibt es nicht.
