# Tasks: csv-logger-import

## 1. Gemeinsame Bausteine

- [x] 1.1 `FileFormatID.v900` und `FileFormatID.iblueCSV` anlegen, dazu `V900FileFormat` und `IBlueCSVFileFormat` (zunächst ohne Leselogik) mit den Namen `format.v900` und `format.iblue-csv` (de, en) und der Endung `csv`. Beide in `FileFormats.all` eintragen. Prüfen: Der Katalogtest findet alle neun Kennungen samt Endungen (Spec `logger-kit`, Szenario „Katalog abfragen“), der Lokalisierungstest ist grün.
- [x] 1.2 `CSVRecords` nach design.md D2: Zeilen, BOM, Felder trimmen (Leerzeichen, Tabulator, NUL), leere Zeilen überspringen, Kopfzeile mit Spaltensuche, abschließendes leeres Feld, Zahlen.
- [x] 1.3 Tests zu 1.2. Prüfen: Die Szenarien „Felder mit Füllbytes“ und „Leere Zeile am Ende“ der Spec `csv-logger-import` sind abgedeckt, außerdem CR, LF und CRLF, ein BOM und eine Zeile mit weniger Feldern als die Kopfzeile.

## 2. V-900

- [x] 2.1 `V900FileFormat.read` nach D3 und D6: Kopfzeile, Datum, Zeit, Position mit Hemisphäre, Höhe, Geschwindigkeit, Kurs, Fix-Art, DOP, Markierungen und Track pro Datei, Abbruch pro Zeile.
- [x] 2.2 Tests zu 2.1 mit kleinen Texten im Test. Prüfen:
  - Die Szenarien „Einfacher Modus“, „Südlich und westlich“, „Professioneller Modus“, „Differentielles GPS“, „Negative Höhe“ und „Ungültige Hemisphäre“ der Spec `csv-logger-import` sind abgedeckt.
  - Ebenso „Markierung per Taste“, „Sprachaufnahme“, „Unbrauchbare Zeile“ und „Zwei Aufzeichnungen“.
  - Das Szenario „Breite außerhalb des Bereichs“ ist abgedeckt: Eine Breite über 90° ergibt `invalidCoordinate`. Ein Datum `261332` ergibt `malformedRecord`.
  - Eine Datei ohne V-900-Kopfzeile endet mit `.malformed(line: 1)`.
  - Der Abbruch einer Datei mit über 50 MB endet in weniger als einer Sekunde mit `CancellationError`.

## 3. iBlue-CSV

- [x] 3.1 `IBlueCSVFileFormat.read` nach D4 und D6: Spaltenzuordnung, beide Datumsformen, Zeit mit Bruchteilen, Vorzeichen aus der Hemisphäre, Höhe, Geschwindigkeit, Kurs, Fix-Art, DOP, Satelliten und Track pro Datei, Abbruch pro Zeile.
- [x] 3.2 Tests zu 3.1 mit kleinen Texten im Test. Prüfen:
  - Die Szenarien „Export eines iBlue 747“, „Datum eines iBlue 757“, „Andere Spaltenreihenfolge“, „Vorzeichen im Zahlenwert“, „Satelliten“, „Unbekannte Werte“ und „Millisekunden“ der Spec `csv-logger-import` sind abgedeckt.
  - Das Szenario „Pflichtspalte fehlt“ ist abgedeckt: Fehlt die Spalte `E/W`, endet das Lesen mit `.malformed(line: 1)`.
  - Ein Datum `2026-11-02` und ein `N/S`-Wert `X` ergeben `malformedRecord`.
  - Der Abbruch einer Datei mit über 50 MB endet in weniger als einer Sekunde mit `CancellationError`.

## 4. Erkennung

- [x] 4.1 `matches(prefix:)` beider Formate nach D5.
- [x] 4.2 Tests zu 4.1. Prüfen: Die Szenarien „V-900-Datei mit Endung .CSV“, „iBlue-Datei“ und „Fremde CSV-Datei“ der Spec `csv-logger-import` sind abgedeckt. Eine V-900-Kopfzeile löst `iblue-csv` nicht aus und umgekehrt, und NMEA-, GPX- und IGC-Testdaten lösen keines der beiden Formate aus.

## 5. Fixtures und Dokumentation

- [x] 5.1 Fixtures nach D8 schreiben: `v900-simple.csv` und `v900-pro.csv` mit einem kleinen Skript im Scratchpad. `iblue747.csv` und `iblue757.csv` erzeugt das gpsbabel-Binary aus `iblue-source.gpx`. Prüfen: gpsbabel 1.7.0 liest alle vier Dateien ohne Meldung „malformed“.
- [x] 5.2 Fixture-Test: Alle vier Fixtures werden über `FileFormats.detect` und `FileFormats.read` gelesen. Verglichen werden Tracks, Punktanzahl, erste und letzte Position, Zeiten, Höhen, Geschwindigkeit, Fix-Art und Wegpunkte. Prüfen: Die geschriebene GPX-Datei ist unter macOS gültig nach dem GPX-1.1-Schema.
- [x] 5.3 Black-Box-Gegenprüfung: Die GPX-Ausgabe aller vier Fixtures mit der von gpsbabel 1.7.0 vergleichen (`-i v900` bzw. `-i iblue747`/`-i iblue757`, `-o gpx`). Prüfen: Punktanzahl, Positionen, Zeiten, Höhen und Geschwindigkeiten stimmen überein. Abweichungen werden in `PROVENANCE.md` notiert.
- [x] 5.4 `PROVENANCE.md` um die Abschnitte `v900` und `iblue-csv` ergänzen (D1, mit den Beobachtungen vom 2026-11-13), dazu die Formattabelle im README des Pakets und die Formatliste im README des Repositorys. In `openspec/config.yaml` die Zuordnung „CSV-Logger (V-900, iBlue-CSV): GPSLoggerKit, Clean-Room, Bestätigung ausstehend“ eintragen und GoPal als offen vermerken. Prüfen: Der Provenance-Test ist grün, und `config.yaml` bleibt unter 51 200 Byte.

## 6. Abschluss

- [x] 6.1 Prüfen, dass alles grün ist:
  - `swift test` im Paket und alle Tests auf dem iOS-27.1-Simulator;
  - das Paket wie bisher in den Scratchpad kopiert und dort getestet;
  - `swift test` für GPSLoaderKit und `xcodebuild test` für die App;
  - `openspec validate csv-logger-import --strict`.

  Die App zeigt im Bereich „Dateien“ die neuen Formate (Snapshot).
- [ ] 6.2 [manuell, Hardware] Der Entwickler konvertiert in der App echte Dateien einer Columbus V-900 bzw. Visiontac VGPS-900 und, falls vorhanden, einen CSV-Export der iBlue-Software. Prüfen:
  - Punktanzahl, Zeiten (UTC oder Ortszeit?), Höhen und Wegpunkte sind plausibel und stimmen mit gpsbabel 1.7.0 überein.
  - Abweichende Kopfzeilen werden notiert.
- [x] 6.3 [manuell] Der Entwickler bestätigt die Zuordnung der Familie zu GPSLoggerKit (Clean-Room), siehe proposal.md, oder entscheidet anders. Prüfen: In `openspec/config.yaml` ist der Vermerk „Bestätigung ausstehend“ entfernt oder die Zuordnung geändert.
