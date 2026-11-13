# Tasks: magellan-port

## 1. Sätze und Dateiformat

- [x] 1.1 `Magellan/MagellanSentences.swift` nach design.md D1/D2, mit Dateikopf nach den Regeln des GPL-Pakets. Tests: Prüfen, dass die Szenarien „Tracksatz“ und „Wegpunkt mit Komma im Kommentar“ der Spec `magellan-import` abgedeckt sind.
- [x] 1.2 `Magellan/MagellanFileFormat.swift` nach D4/D5. Tests mit `MagellanTestFile`: Prüfen, dass die Szenarien „Tracklog-Datei“, „Wegpunktdatei“, „Falsche Prüfsumme“ und „NMEA-Datei“ abgedeckt sind.
- [x] 1.3 `GPLFileFormats.all`, Lokalisierung des Formatnamens (de/en), `PROVENANCE.md` und `README.md` des Pakets. Prüfen: Das Szenario „Magellan-Format abfragen“ der Spec `logger-kit-gpl` ist durch einen Test abgedeckt.

## 2. Gerät

- [x] 2.1 `Magellan/MagellanDevice.swift` nach D3/D4/D6.
- [x] 2.2 Tests mit `MagellanSimulator`. Prüfen: Die Szenarien „Prüfsumme eines Befehls“, „Gerät verstummt“, „Meridian meldet sich“, „Unbekanntes Gerät“, „Falsche Baudrate“, „Auslesen“ und „Keine Wegpunkte“ der Spec `magellan-device` sind abgedeckt.
- [x] 2.3 `DeviceDrivers/Families/MagellanDevices.swift` (sieben Geräte) und `DeviceCatalogContent`. Prüfen: Das Szenario „Magellan-Gerät wählen“ ist durch einen Test abgedeckt.
- [x] 2.4 `openspec/config.yaml`: Magellan aus „Weiterhin über gpsbabel“ in die Zuordnungsliste des GPL-Pakets (Change `magellan-port`).

## 3. Gegenprüfung und Abschluss

- [x] 3.1 Fixtures und Black-Box nach D7 (Dateien und pty-Simulator). Prüfen: Die Ergebnisse stehen in `PROVENANCE.md`, und alle Tests sowie `openspec validate magellan-port --strict` sind grün.
- [ ] 3.2 [manuell, Hardware] Der Entwickler liest einen Magellan Meridian oder SporTrak über die serielle Schnittstelle aus und konvertiert eine `.log`-Datei von der SD-Karte. Prüfen: Track und Wegpunkte stimmen mit gpsbabel 1.7.0 überein.
