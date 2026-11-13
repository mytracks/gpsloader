# Tasks: wintec-file-port

## 1. Leser

- [x] 1.1 `WintecTime` in `Wintec/WintecFileFormats.swift` nach design.md D2 und D3: Zeitstempel und Prüfung. Prüfen: Das Szenario „Zeitstempel“ der Spec `wintec-import` ist abgedeckt. Ein Monat 0 und ein Jahr unter 2004 sind ungültig.
- [x] 1.2 `WintecTESFileFormat` nach D1–D4 mit Dateikopf nach Regel 6, Name `format.wintec-tes` (de, en).
- [x] 1.3 `WintecBinFileFormat` und `WintecTK1FileFormat` mit gemeinsamem Leser nach D1–D4, Namen `format.wbt-bin` und `format.wbt-tk1` (de, en). Alle drei Formate in `GPLFileFormats.all` eintragen, `credits` um Robert Lipe ergänzen.
- [x] 1.4 Erkennung nach D5.

## 2. Tests

- [x] 2.1 Test-Encoder `WintecTestFile` nach D7 und Tests. Prüfen:
  - Abgedeckt sind alle Szenarien der Spec `wintec-import`: „Aufzeichnung eines WBT-202“, „Abgeschnittene TES-Datei“, „Neuer Track im Norden“, „Datensätze mit Höhe“, „Keine gültige Länge“, „Zwei Tracks und ein Wegpunkt“ und „Mehrere Tracks“.
  - Ebenso die Erkennungsszenarien „TK1-Datei“, „TES-Datei“ und „Andere Abbilder“, dazu das Szenario „Wintec-Formate abfragen“ der Spec `logger-kit-gpl`.
  - Eine BIN-Datei mit Breite -150° beginnt einen neuen Track im Süden.
  - Der Abbruch einer Datei mit über 50 MB endet in weniger als einer Sekunde.

## 3. Fixtures und Gegenprüfung

- [x] 3.1 Fixtures `wbt202.tes`, `wbt200.bin` und `wbt201.tk1` mit dem Encoder erzeugen. Dazu kommen ein Vergleich mit der Encoder-Ausgabe und Fixture-Tests über den Katalog der App. Prüfen: Die GPX-Ausgabe ist mit `xmllint` gültig nach dem GPX-1.1-Schema.
- [x] 3.2 Black-Box-Gegenprüfung mit dem gpsbabel-1.7.0-Binary nach D7. Prüfen: Übereinstimmung bis auf D4, das Ergebnis steht in `PROVENANCE.md`.

## 4. Dokumentation

- [x] 4.1 Ergänzt werden `PROVENANCE.md` (drei Abschnitte), die README des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` (Wintec: Dateiformate portiert). Prüfen: Der Provenance-Test und `openspec validate --all --strict` sind grün.

## 5. Abschluss

- [x] 5.1 Prüfen, dass alles grün ist: `swift test` in GPSLoggerKitGPL und GPSLoaderKit, `xcodebuild test` für die App, eine Kopie des GPL-Pakets im Scratchpad und `openspec validate wintec-file-port --strict`. Ein Snapshot zeigt das Hauptfenster mit 15 Formaten.
- [ ] 5.2 [manuell, Hardware] Der Entwickler konvertiert in der App eine TES-Datei eines WBT-202 sowie, falls vorhanden, eine BIN- oder TK1-Datei. Prüfen: Punktanzahl, Zeiten und Höhen sind plausibel und stimmen mit gpsbabel 1.7.0 überein.
