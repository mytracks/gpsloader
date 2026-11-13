# Tasks: device-week-rollover

## 1. Adapter

- [x] 1.1 `ProtocolDriver.read` wendet `RecordingProcessing.correctingWeekRollover` mit der Bezugszeit an; die Bezugszeit ist für Tests einstellbar (Standard: aktuelle Zeit).
- [x] 1.2 Tests in `DeviceDriversTests` mit einem simulierten Gerät. Prüfen: Die Szenarien „Logger mit Wochenüberlauf“ und „Aktuelle Zeiten bleiben“ der Spec `device-mode` sind abgedeckt, auch für Wegpunkte.

## 2. GNS 2000

- [x] 2.1 `GNS2000Device` korrigiert die Zeiten vor dem Teilen in Tracks; die Bezugszeit ist für Tests einstellbar.
- [x] 2.2 Test mit `GNS2000Simulator`. Prüfen: Das Szenario „Tracknamen nach der Korrektur“ ist abgedeckt, auch für Speicher, deren Zeiten am Überlauf mitten im Speicher zurückspringen.

## 3. Abschluss

- [x] 3.1 `swift test` in GPSLoggerKit, GPSLoggerKitGPL und GPSLoaderKit, `xcodebuild test` und `openspec validate --all --strict` sind grün.
- [ ] 3.2 [manuell, Hardware] Der Entwickler liest den Holux M-241 erneut aus. Prüfen: Die Zeiten im GPX liegen im richtigen Jahr.
