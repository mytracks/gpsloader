# Tasks: igc-import

## 1. Gemeinsame Bausteine

- [x] 1.1 Zeilenleser und Datumshelfer nach design.md D2 verschieben:
  - `NMEAFileFormat.forEachLine(in:_:)` (samt `lines(of:)`) nach `Formats/TextLines.swift`
  - `NMEASentence.date(ddmmyy:)` und `NMEAFileReader.date(days:timeOfDay:)` nach `Processing/UTCTime.swift`

  Prüfen: Alle bestehenden Tests, insbesondere die NMEA-Tests, laufen unverändert grün.

## 2. IGC-Format

- [x] 2.1 `FileFormatID.igc`, `IGCFileFormat` mit Name, Endung `igc` und Eintrag in `FileFormats.all` anlegen; Lokalisierung `format.igc` (de, en). Prüfen: Der angepasste Katalogtest findet `nmea`, `gpx` und `igc` (Spec `logger-kit`, „Katalog abfragen“), der Lokalisierungstest ist grün.
- [x] 2.2 B-Record-Parser nach design.md D3: Zeit, Breite, Länge, Gültigkeit, Druck- und GNSS-Höhe, Höhenregel, Fix-Art, Warnungen bei kurzen oder fehlerhaften Datensätzen.
- [x] 2.3 Tests zu 2.2 mit synthetischen Datensätzen. Prüfen: Die Szenarien „Gültiger Fix“, „Südlich und östlich“, „Abgeschnittener Datensatz“, „Gerät ohne Drucksensor“, „Fix ohne GNSS-Höhe“ und „Keine Höhe“ der Spec `igc-import` sind abgedeckt, ebenso Minuten ≥ 60 und negative Höhen.
- [x] 2.4 I-Record und `SIU` nach design.md D3, inklusive B-Records, die kürzer sind als eine angekündigte Erweiterung.
- [x] 2.5 Tests zu 2.4. Prüfen: Szenarien „Satelliten“ und „Unbekannte Erweiterung“, dazu ein ungültiger I-Record (Warnung, Punkte ohne Satelliten).
- [x] 2.6 Datum (`HFDTE` in beiden Schreibweisen), Mitternachtswechsel und fehlendes Datum nach design.md D3; ein Track pro Datei mit Dateinamen ohne Endung (D6); übrige Datensätze ignorieren; Abbruch pro Zeile (D5).
- [x] 2.7 Tests zu 2.6. Prüfen: Szenarien „Neue Schreibweise“, „Flug über Mitternacht“, „Fehlendes Datum“, „Zwei Flüge“, „Aufgabendeklaration“ und „Signatur“; ein Abbruchtest mit einer großen synthetischen Datei endet in weniger als einer Sekunde mit `CancellationError`.
- [x] 2.8 Erkennung nach design.md D4.
- [x] 2.9 Tests zu 2.8. Prüfen: Szenarien „Endung fehlt“ und „Keine IGC-Datei“; eine Textdatei, die nur mit `A` beginnt, wird nicht als IGC erkannt; NMEA- und GPX-Fixtures werden weiterhin richtig erkannt.

## 3. Fixtures und Dokumentation

- [x] 3.1 Zwei synthetische Fixtures nach der FAI-Spezifikation anlegen: ein Flug mit A-, H- (alte `HFDTE`-Form), I-, B-, C-, E-, F-, L- und G-Records und CRLF; ein Flug über Mitternacht mit neuer `HFDTEDATE:`-Form und ohne Drucksensor. Prüfen: Ein Test liest beide und vergleicht Punktanzahl, erste und letzte Position und Zeit; die erzeugte GPX-Datei ist unter macOS XSD-gültig.
- [x] 3.2 `PROVENANCE.md` um den Abschnitt `igc` ergänzen (design.md D1), README des Pakets um IGC. Prüfen: Der Provenance-Test ist grün.

## 4. Abschluss

- [x] 4.1 `swift test` im Paket und alle Tests auf dem iOS-27.1-Simulator ausführen; Paket wie bisher in den Scratchpad kopieren und dort testen. Prüfen: alles grün.
- [x] 4.2 `openspec validate igc-import --strict` ausführen. Prüfen: gültig.
- [ ] 4.3 [manuell, Hardware] Der Entwickler stellt echte IGC-Dateien bereit, etwa von einem Vario oder einer Flug-App. Sie werden als zusätzliche Fixtures aufgenommen. Prüfen: Die Tests sind grün, und Punktanzahl sowie Zeitspanne stimmen mit gpsbabel 1.7.0 (`-i igc`, Black-Box) überein.
