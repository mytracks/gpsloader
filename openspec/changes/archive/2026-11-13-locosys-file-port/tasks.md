# Tasks: locosys-file-port

## 1. Leser

- [x] 1.1 `Locosys/LocosysFileFormats.swift` nach design.md D1–D4 mit Dateikopf nach Regel 6: `SBPFileFormat` und `SBNFileFormat`, Namen `format.sbp` und `format.sbn` (de, en). Beide in `GPLFileFormats.all` eintragen, `credits` um Rodney Lorrimar und Tom Hughes ergänzen.
- [x] 1.2 Erkennung nach D5.

## 2. Tests

- [x] 2.1 Test-Encoder `LocosysTestFile` und Tests. Prüfen:
  - Abgedeckt sind alle Szenarien der Spec `locosys-import`: „Zu kurze Datei“, „Datensatz eines GT-31“, „Dezember“, „Keine SBN-Datei“, „Falsche Prüfsumme“, „Navigationspaket“ und „Gültiger 3D-Fix mit DGPS“.
  - Ebenso „Ungültige Lösung“, „SBN-Datei“, „SBP-Datei“ und „Andere Dateien“, dazu „Locosys-Formate abfragen“ der Spec `logger-kit-gpl`.
  - Ein Rahmenfehler in SBN beendet das Lesen mit einer Warnung.
  - Der Abbruch einer Datei mit über 50 MB endet in weniger als einer Sekunde.

## 3. Fixtures und Gegenprüfung

- [x] 3.1 Fixtures `gt31.sbp` und `gt31.sbn` mit dem Encoder erzeugen. Dazu kommen ein Vergleich mit der Encoder-Ausgabe und Fixture-Tests über den Katalog der App. Prüfen: Die GPX-Ausgabe ist mit `xmllint` gültig nach dem GPX-1.1-Schema.
- [x] 3.2 Black-Box-Gegenprüfung mit dem gpsbabel-1.7.0-Binary nach D7. Prüfen: Übereinstimmung, das Ergebnis steht in `PROVENANCE.md`.

## 4. Dokumentation

- [x] 4.1 Ergänzt werden `PROVENANCE.md` (zwei Abschnitte), die README des GPL-Pakets, das README des Repositorys und `openspec/config.yaml`: SBP/SBN wandern aus „Weiterhin über gpsbabel“ zu den portierten Formaten, Navilink/Locosys gilt als Dateiformate portiert. Prüfen: Der Provenance-Test und `openspec validate --all --strict` sind grün.

## 5. Abschluss

- [x] 5.1 Prüfen, dass alles grün ist: `swift test` in GPSLoggerKitGPL und GPSLoaderKit, `xcodebuild test` für die App, eine Kopie des GPL-Pakets im Scratchpad und `openspec validate locosys-file-port --strict`. Ein Snapshot zeigt das Hauptfenster mit 17 Formaten.
- [ ] 5.2 [manuell, Hardware] Der Entwickler konvertiert in der App eine SBP- und eine SBN-Datei eines Locosys-Loggers. Prüfen: Die Dateien werden erkannt, und Punktanzahl, Zeiten und Positionen stimmen mit gpsbabel 1.7.0 überein.
