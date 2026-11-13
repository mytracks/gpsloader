# Tasks: fit-tcx-suunto-import

## 1. Gemeinsame Bausteine

- [x] 1.1 Die Erkennung des Wurzelelements aus `GPXFileFormat.matches` nach `Formats/XMLSniffer.swift` verschieben (design.md D2). Prüfen: Alle GPX-Tests und die Erkennungstests laufen unverändert grün.
- [x] 1.2 `ImportWarningKind.fileChecksumMismatch` und `.truncatedFile` mit Meldungen nur mit Dateinamen anlegen (D6), dazu die Lokalisierung (de, en). Prüfen: Ein Test prüft beide Meldungen auf Deutsch und Englisch, der Lokalisierungstest ist grün (Spec `logger-kit`, „Fehler und Warnungen“).
- [x] 1.3 `FileFormatID.fit`, `.tcx` und `.suuntoSML` (`suunto-sml`) anlegen. Die drei Formate werden in `FileFormats.all` eingetragen, mit Namen (`format.fit`, `format.tcx`, `format.suunto-sml`, de/en) und Endungen. Prüfen: Der Katalogtest findet alle sechs Kennungen (Szenario „Katalog abfragen“).

## 2. FIT

- [x] 2.1 Die Nachrichten- und Feldnummern aus design.md D3 gegen das aktuelle FIT-Profil (developer.garmin.com, FIT SDK `Profile.xlsx`) prüfen und die Quellen samt Stand in `PROVENANCE.md` (Abschnitt `fit`) festhalten. Prüfen: Die Tabelle in D3 stimmt mit dem Profil überein oder ist korrigiert.
- [x] 2.2 Test-Encoder `FITTestFile` im Testziel (D8): Kopf mit 12 und 14 Byte, Definitionen in LE und BE, Entwicklerfelder, Datennachrichten, komprimierte Zeitstempel und CRC-16. Prüfen: Die CRC einer bekannten Bytefolge stimmt mit dem Prüfwert von CRC-16/ARC überein (`"123456789"` ergibt 0xBB3D).
- [x] 2.3 `FITDecoder` nach D3: Kopf, Record-Header, Definitionstabelle, Basistypen und Ungültigkeitswerte, Überspringen unbekannter Felder und Entwicklerfelder, Zeitstempel (absolut, relativ, komprimiert), verkettete Dateien, CRC-Prüfung, beschädigte Dateien.
- [x] 2.4 Tests zu 2.3. Prüfen: Die Szenarien „Big-Endian-Definition“, „Entwicklerfelder“, „Komprimierter Zeitstempel“ (auch mit Überlauf der 5 Bit), „Verkettete Dateien“, „Abgeschnittene Aktivität“, „Falsche Prüfsumme“ (Kopf und Datei) und „Ungültiger Kopf“ der Spec `fit-import` sind abgedeckt. Dazu kommt eine Datennachricht mit undefinierter lokaler Art.
- [x] 2.5 `FITFileFormat`: Punkte aus `record`, Höhe und Geschwindigkeit nach Vorrang, Segmente über Timer-Ereignisse, Track-Name aus `course` oder Dateiname, Wegpunkte aus `course_point`, Abbruch pro Nachricht (D7).
- [x] 2.6 Tests zu 2.5. Prüfen:
  - Die Szenarien „Punkt umrechnen“, „Erweiterte Höhe“, „Nur Herzfrequenz“, „Relative Gerätezeit“, „Pause in einer Aktivität“, „Kursdatei“, „Zwei Dateien“ und „Kurspunkt“ sind abgedeckt.
  - `stop_all` ohne nachfolgenden `start` öffnet beim nächsten Punkt ein neues Segment.
  - Eine Datei ohne Positionen endet mit „keine verwertbaren Daten“.
  - Der Abbruch einer großen Datei endet in weniger als einer Sekunde mit `CancellationError`.
- [x] 2.7 Erkennung nach Spec `fit-import`, „Erkennung“. Prüfen: Die Szenarien „Endung fehlt“ und „Andere Binärdatei“ sind abgedeckt; eine Datei mit weniger als 12 Byte wird nicht erkannt.

## 3. TCX

- [x] 3.1 `TCXFileFormat` mit `TCXParserHandler` nach D4: Aktivitäten, Runden und Tracks als Segmente, Trackpunkte mit TPX-Geschwindigkeit, Kurse mit Namen, Kurspunkte als Wegpunkte, übergangene Teilbäume, Warnungen, Abbruch, Erkennung über `XMLSniffer`.
- [x] 3.2 Synthetische Fixtures `activity.tcx` (zwei Runden, Trackpunkt ohne Position, Workout) und `course.tcx` (Kurs mit zwei Kurspunkten) nach `TrainingCenterDatabasev2.xsd`.
- [x] 3.3 Tests zu 3.1 und 3.2. Prüfen:
  - Die Szenarien „Zwei Runden“, „Zwei Aktivitäten“, „Punkt mit Geschwindigkeit“, „Pause ohne Position“, „Ungültige Breite“, „Kurs mit Kurspunkten“, „Workout“, „Abgeschnittene Datei“, „TCX mit Endung .xml“ und „GPX bleibt GPX“ der Spec `tcx-import` sind abgedeckt.
  - Ein fehlender `Time`-Wert ergibt `missingDate`.
  - Der Abbruchtest endet in weniger als einer Sekunde.

## 4. Suunto SML

- [x] 4.1 `SuuntoSMLFileFormat` mit `SuuntoParserHandler` nach D5: Proben, Umrechnung aus dem Bogenmaß, Höhenregel, Pausen als Segmente, Track mit Dateinamen, Warnungen, Abbruch, Erkennung über `XMLSniffer`.
- [x] 4.2 Synthetische Fixture `ambit.sml` mit erfundenen Koordinaten und dem Aufbau aus D1: Kopf, `periodic`-, `gps-base`- und `gps-small`-Proben sowie Pause-Ereignisse am Anfang, in der Mitte und am Ende. Dazu dieselbe Datei als `.xml`. Werte aus der myTracks-Beispieldatei werden nicht übernommen.
- [x] 4.3 Tests zu 4.1 und 4.2. Prüfen:
  - Die Szenarien „GPS-Probe umrechnen“, „Periodische Probe“, „Barometrische Höhe“, „Nur GPS-Höhe“, „Aufzeichnung mit Pause“, „Startereignis“, „Abgeschnittene Datei“ und „SML mit Endung .xml“ der Spec `suunto-import` sind abgedeckt.
  - Ein Kurs über 2π wird normalisiert.
  - Der Abbruchtest endet in weniger als einer Sekunde.

## 5. Fixtures und Dokumentation

- [x] 5.1 Die FIT-Fixtures `activity.fit` (mit Pause) und `course.fit` (Kurs mit Kurspunkten) mit dem Test-Encoder erzeugen und unter `Fixtures/` ablegen (D8). Prüfen: Ein Test liest alle fünf neuen Fixtures (`activity.fit`, `course.fit`, `activity.tcx`, `course.tcx`, `ambit.sml`) über `FileFormats.detect` und `FileFormats.read` und vergleicht Punktanzahl, erste und letzte Position und Zeit. Die daraus geschriebene GPX-Datei ist unter macOS gültig nach dem GPX-1.1-Schema.
- [x] 5.2 `PROVENANCE.md` um die Abschnitte `tcx` und `suunto-sml` ergänzen (D1, `fit` kommt aus 2.1), dazu die Formattabelle im README des Pakets und die Strukturtabelle im README des Repositorys. Prüfen: Der Provenance-Test ist grün.

## 6. Abschluss

- [x] 6.1 `swift test` im Paket und alle Tests auf dem iOS-27.1-Simulator ausführen. Das Paket wie bisher in den Scratchpad kopieren und dort testen. Dazu `swift test` für GPSLoaderKit und `xcodebuild test` für die App. Prüfen: alles grün. Die App zeigt im Bereich „Dateien“ die neuen Formate (Snapshot).
- [x] 6.2 `openspec validate fit-tcx-suunto-import --strict` ausführen. Prüfen: gültig.
- [ ] 6.3 [manuell, Hardware] Der Entwickler konvertiert in der App echte Dateien, etwa FIT einer Garmin-Uhr oder des Canmore GP-102+, TCX aus Garmin Connect sowie SML/XML aus Moveslink. Prüfen:
  - Punktanzahl, erste und letzte Position und Zeitspanne stimmen mit gpsbabel 1.7.0 (`garmin_fit` bzw. `gtrnctr`, Black-Box) überein.
  - Bei Suunto ist der Track vollständig und plausibel, mit Höhe und Pausen.
  - Moveslink-Rohdateien ohne `sml`-Wurzel werden notiert. Wenn es sie gibt, folgt ein eigener Change.
