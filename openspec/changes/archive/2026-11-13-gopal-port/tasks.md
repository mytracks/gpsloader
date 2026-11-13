# Tasks: gopal-port

## 1. Leser

- [x] 1.1 `GoPal/GoPalFileFormat.swift` nach design.md D1–D4 mit Dateikopf nach Regel 6, Name `format.gopal` (de, en), Eintrag in `GPLFileFormats.all`. `credits` um Jürgen Neumann ergänzen.
- [x] 1.2 Erkennung nach D5.

## 2. Tests

- [x] 2.1 Tests mit kleinen Texten. Prüfen:
  - Abgedeckt sind alle Szenarien der Spec `gopal-import`: „Zeile mit Datum“, „Datum im Dateinamen“, „Über Mitternacht“, „Kein Datum“, „Sprung in den Daten“, „Track statt Route“, „GoPal-Datei“ und „Andere CSV-Datei“.
  - Ebenso „GoPal abfragen“ der Spec `logger-kit-gpl`.
  - Der Dateiname `A_20261102_093000.trk` wird ebenfalls erkannt.
  - Der Abbruch einer Datei mit über 50 MB endet in weniger als einer Sekunde.

## 3. Fixture und Gegenprüfung

- [x] 3.1 Fixture `track20261102_080000.trk` nach D7 und Fixture-Test über den Katalog der App. Prüfen: Die GPX-Ausgabe ist mit `xmllint` gültig nach dem GPX-1.1-Schema.
- [x] 3.2 Black-Box-Gegenprüfung mit dem gpsbabel-1.7.0-Binary nach D7. Prüfen: Positionen und Höhen stimmen überein, das Ergebnis steht in `PROVENANCE.md`.

## 4. Dokumentation

- [x] 4.1 Ergänzt werden `PROVENANCE.md`, die README des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` (GoPal portiert). Prüfen: Der Provenance-Test und `openspec validate --all --strict` sind grün.

## 5. Abschluss

- [x] 5.1 Prüfen, dass alles grün ist: `swift test` in GPSLoggerKitGPL und GPSLoaderKit, `xcodebuild test` für die App, eine Kopie des GPL-Pakets im Scratchpad und `openspec validate gopal-port --strict`. Ein Snapshot zeigt das Hauptfenster mit 18 Formaten.
- [ ] 5.2 [manuell, Hardware] Der Entwickler konvertiert in der App eine `.trk`-Datei eines Medion-GoPal-Geräts. Prüfen: Datum, Zeiten, Positionen und Geschwindigkeit sind plausibel.
