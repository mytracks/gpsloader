# Tasks: gpsloggerkit-foundation

## 1. Paketgerüst

- [x] 1.1 `Packages/GPSLoggerKit` nach design.md D1 anlegen:
  - `Package.swift` mit Tools 6.0, `.macOS(.v12)`, `.iOS("27.0")`, Swift 6 und `defaultLocalization "en"`
  - Ziel `GPSLoggerKit` und Testziel `GPSLoggerKitTests` mit Swift Testing
  - `LICENSE` (MIT), `README.md` mit Zweck, Plattformen und Clean-Room-Regel, `PROVENANCE.md` als Gerüst

  Prüfen: `swift build --package-path Packages/GPSLoggerKit` läuft ohne Warnungen. `xcodebuild build -scheme GPSLoggerKit -destination 'generic/platform=iOS Simulator'` im Paketordner gelingt.
- [x] 1.2 `GPSLoggerError` und `ImportWarning` nach design.md D4 anlegen, mit `Localizable.xcstrings` (de, en) in `Bundle.module`. Prüfen: Ein Test liest für jede Fehlerart die deutsche und die englische Meldung, und keine ist leer oder gleich dem Schlüssel.

## 2. Datenmodell und GPX-Ausgabe

- [x] 2.1 Modelltypen aus `GPSLoaderKit/Sources/LoggerCore/Model.swift` ins Paket übernehmen und nach design.md D2 erweitern: `speed`, `course`, `satellites`, `hdop`, `vdop`, `pdop`, `FixType`, auch an `Waypoint`. Prüfen: Die übernommenen `ModelTests` laufen, und ein neuer Test belegt, dass ein Punkt nur mit Koordinaten alle übrigen Angaben leer hat (Spec `logger-kit`, „Punkt nur mit Koordinaten“).
- [x] 2.2 `GPXWriter` ins Paket übernehmen (design.md D7):
  - Qualitätsangaben in Schemareihenfolge ausgeben
  - `writeFailed` als `GPSLoggerError` melden
  - `creator` als Pflichtparameter

  Die bestehenden `GPXWriterTests`, `GPXWriterConcurrencyTests` und `gpx.xsd` wandern mit; die XSD-Prüfung läuft nur unter macOS. Prüfen:
  - Die übernommenen Tests bestehen mit unveränderten Erwartungen, die Ausgabe ist also byteidentisch.
  - Neue Tests decken die Szenarien „Punkt mit Qualitätsangaben“ (XSD-gültig) und „Geschwindigkeit wird nicht ausgegeben“ aus der Spec `gpx-export` ab.

## 3. Formatvertrag und Nachbearbeitung

- [x] 3.1 `FileFormat`, `FileFormatID`, `FileInput` (inklusive `load(_ url:)`), `ImportOptions`, `ImportResult`, den Katalog `FileFormats.all` und `FileFormats.detect(prefix:fileName:)` nach design.md D3 umsetzen. Prüfen: Tests mit einem Testformat decken ab:
  - „Zwei Dateien“ (Reihenfolge der Übergabe)
  - „Unbekannter Inhalt“ (JPEG-Header ergibt `nil`)
  - „Leere Datei“ (Fehler nennt den Dateinamen)
- [x] 3.2 Abbruch umsetzen: Prüfung alle 4096 Einheiten, `CancellationError` sowie die `async`-Hülle von `read`. Prüfen: Ein Test bricht das Einlesen großer synthetischer Eingaben ab. Das Ergebnis ist `CancellationError` ohne Teilergebnis, und das Einlesen endet zeitnah, also in weniger als einer Sekunde.
- [x] 3.3 `RecordingProcessing` nach design.md D8 umsetzen: Wochenüberlauf für Trackpunkte und Wegpunkte, Wegpunkte als Track. Beides wird in `FileFormats.read` über `ImportOptions` eingebunden. Prüfen: Tests decken „Logger mit Wochenüberlauf“ (15.03.2007 wird mit Referenz 03.11.2026 zum 29.10.2026), „Korrektur abgeschaltet“ und „Datei nur mit Wegpunkten“ aus der Spec `logger-kit` ab.
- [x] 3.4 Herkunftsprüfung: Ein Test stellt sicher, dass jede `FileFormatID` aus `FileFormats.all` in `PROVENANCE.md` einen Abschnitt hat. Prüfen: Der Test scheitert, wenn ein Abschnitt entfernt wird, und besteht mit vollständiger Datei.

## 4. NMEA-0183-Import

- [x] 4.1 Zeilenzerlegung und Satzprüfung nach design.md D5:
  - LF, CR und CRLF als Zeilenende
  - nur `$`-Zeilen auswerten
  - Prüfsumme (XOR) prüfen, Sätze ohne Prüfsumme akzeptieren
  - Talker erkennen und `$P…` überspringen

  Fixtures dafür selbst erstellen. Prüfen: Tests decken „Sony-Logdatei“ (`@`-Zeilen), „Falsche Prüfsumme“ (Warnung mit Anzahl), „Abgeschnittene letzte Zeile“, „Multi-GNSS-Logger“ und „Satellitenstatus“ ab.
- [x] 4.2 Feldauswertung für RMC, GGA, GLL, GSA, VTG, ZDA und WPL:
  - `ddmm.mmmm` in Grad umrechnen, Knoten in m/s
  - Fix-Status auswerten, Werte außerhalb des Wertebereichs als Warnung zählen

  Prüfen: Tests pro Satztyp mit Grenzfällen (leere Felder, Südhalbkugel, Westlänge) sowie „Logger ohne Empfang“ und „WPL-Satz“ (HOME bei 51,741157/8,680967).
- [x] 4.3 Epochen und Datum: Sätze derselben UTC-Zeit zusammenfassen, VTG nur als Ersatz für Geschwindigkeit und Kurs, Datum aus RMC/ZDA, Mitternachtsübergang, Rückdatierung von Punkten vor dem ersten Datum, zweistellige Jahre als 1980–2079, Warnung `missingDate`. Prüfen: Tests decken „RMC und GGA zur selben Sekunde“, „Nur GGA“, „Mitternacht“, „GGA vor dem ersten RMC“ und „Datei ganz ohne Datum“ ab, außerdem Millisekunden in der Zeit.
- [x] 4.4 Track-Aufteilung: ein Track pro Einlese-Operation, ein neues Segment pro Datei und bei einem Zeitrücksprung. Das NMEA-Format wird mit Kennung `nmea` und den Endungen `nmea`, `nma`, `txt`, `log` und `gps` im Katalog registriert. Prüfen: Tests decken „Drei Dateien eines Tages“ und „Zeitrücksprung“ ab.
- [x] 4.5 NMEA-Erkennung: mindestens drei gültige Sätze in den ersten 4 KB. Prüfen: Tests decken „NMEA mit falscher Endung“ und „Canon-EOS-Log“ (selbst erstellte Datei mit Kopfzeile) ab, außerdem eine Negativprobe mit einer CSV-Datei.
- [x] 4.6 `PROVENANCE.md`, Abschnitt `nmea`, ausfüllen: verwendete öffentliche Satzbeschreibungen mit Fundstelle sowie das `@`-Verhalten aus dem eigenen myTracks-Code mit Datei und Zeile. Prüfen: Der Test aus 3.4 besteht.

## 5. GPX-Eingang

- [x] 5.1 ISO-8601-Parser nach design.md D6: Datum, Zeit, optionaler Bruchteil, `Z`, `±hh:mm` oder ohne Zone als UTC. Prüfen: Tests decken „Zeit mit Zonenversatz“, Bruchteile, ungültige Werte (Ergebnis `nil`) sowie Jahre vor 1970 ab.
- [x] 5.2 GPX-Parser auf `XMLParser`-Basis:
  - Erkennung über lokale Namen
  - `trk`/`trkseg`/`trkpt` und `wpt` mit allen Punktangaben, bei GPX 1.0 zusätzlich `speed` und `course`
  - `extensions` und `rte` ignorieren

  Prüfen: Tests mit selbst erstellten Fixtures decken ab:
  - „GPX 1.0 eines älteren Garmin-Geräts“
  - „Ohne Namensraum“
  - „Garmin-Datei mit Tracks, Wegpunkten und Route“
  - „Garmin-Erweiterungen“
- [x] 5.3 Fehler und Warnungen: ungültige Koordinaten als Warnung, nicht wohlgeformtes XML als Fehler mit Zeile und ohne Teilergebnis. Prüfen: Tests decken „Punkt außerhalb des Wertebereichs“ und „Abgeschnittene Datei“ ab.
- [x] 5.4 GPX-Format mit Kennung `gpx` und den Endungen `gpx` und `xml` registrieren, Erkennung über das erste Element `gpx`. Prüfen:
  - Ein Test deckt „GPX mit Endung `.xml`“ ab, dazu eine Negativprobe mit einer anderen XML-Datei (z. B. KML).
  - Ein Rundlauftest liest eine eigene Ausgabe ein und erhält dasselbe Modell.
- [x] 5.5 `PROVENANCE.md`, Abschnitt `gpx`, ausfüllen: Topografix-Schemas für GPX 1.0 und 1.1 mit URL. Prüfen: Der Test aus 3.4 besteht.

## 6. Umstellung von GPSLoaderKit und App

- [x] 6.1 `GPSLoaderKit` hängt per `.package(path: "../GPSLoggerKit")` vom neuen Paket ab, und `LoggerCore/Model.swift` entfällt. Alle Stellen, die die Modelltypen nutzen (`Driver`, `LoggerSession`, `TestSupport`, Tests), importieren `GPSLoggerKit`. Prüfen: `swift test --package-path Packages/GPSLoaderKit` ist grün.
- [x] 6.2 In `GPXExport` entfällt `GPXWriter.swift`. Es bleiben `GPXFileName` und eine dünne Schreibfunktion, die `GPSLoggerError(.writeFailed)` in `LoggerError(.writeFailed)` übersetzt. Die App (`SessionPresenter`, `DemoDriver`) wird umgestellt. Prüfen:
  - Ein Test in `GPXExportTests` belegt die Fehlerübersetzung.
  - Der Test „Ziel nicht beschreibbar“ besteht weiterhin.
- [x] 6.3 `xcodegen generate`, App-Build und `xcodebuild test` ausführen. Falls die transitive Paketauflösung nicht greift, `GPSLoggerKit` in `project.yml` als lokales Paket ergänzen (design.md D9). Prüfen:
  - Build und alle Tests sind grün.
  - `swift Scripts/check-localizations.swift` ist fehlerfrei.
  - Der Ende-zu-Ende-Lauf mit dem Demo-Treiber (`-DebugDemo success`) erzeugt eine GPX-Datei, die gegen das XSD validiert.

## 7. Integration

- [x] 7.1 Eigenständigkeit prüfen: `Packages/GPSLoggerKit` in ein leeres Verzeichnis im Scratchpad kopieren und dort `swift build` und `swift test` ausführen. Prüfen: beides grün, ohne Verweise auf das übrige Repository.
- [x] 7.2 Alle Tests von `GPSLoggerKit` auf dem iOS-27.1-Simulator ausführen (`xcodebuild test -scheme GPSLoggerKit -destination 'platform=iOS Simulator,…'`). Prüfen: alle Tests grün; nur die XSD-Prüfungen sind dort per `#if os(macOS)` ausgeklammert.
- [x] 7.3 Last- und Speichertest: eine synthetische NMEA-Datei von 50 MB (RMC+GGA, 1 Hz) erzeugen und einlesen, unter macOS und auf dem iOS-Simulator. Prüfen:
  - Die Laufzeit liegt auf dem Mac unter 5 Sekunden (Release-Build).
  - Der maximale Speicherbedarf (`/usr/bin/time -l` bzw. Instruments) liegt unter 200 MB.
  - Die Ergebnisse werden in design.md D5 festgehalten.
- [x] 7.4 `openspec validate gpsloggerkit-foundation --strict` ausführen. Prüfen: gültig.
- [ ] 7.5 [manuell, Hardware] Der Entwickler stellt echte NMEA- und GPX-Dateien eigener Geräte bereit, z. B. Sony CS-1, Canon EOS, Garmin. Sie werden als zusätzliche Fixtures aufgenommen. Prüfen: Die Tests mit diesen Dateien sind grün, und Punktanzahl sowie Zeitspanne stimmen mit der Ausgabe von gpsbabel 1.7.0 überein. Dafür wird gpsbabel als Black-Box mit Rosetta oder auf einem Intel-Mac gestartet.
- [ ] 7.6 [manuell, Hardware] Die Tests von `GPSLoggerKit` auf einem echten iPhone oder iPad mit iOS 27 ausführen. Prüfen: alle Tests grün.

## Workflow follow-up

- Nach Abschluss und Review den Change archivieren (`/opsx:archive`).
- Danach folgen die Changes für die weiteren Familien gemäß `openspec/config.yaml` (Abschnitt GPSLoggerKit, Reihenfolge).
