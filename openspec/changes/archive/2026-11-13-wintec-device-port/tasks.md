# Tasks: wintec-device-port

## 1. Treiber

- [x] 1.1 `Wintec/WintecDevice.swift` nach design.md D1/D2 mit Dateikopf nach Regel 6, dazu `WintecLog.readWBT201Records` herauslösen.
- [x] 1.2 Tests mit `WintecSimulator`. Prüfen: Abgedeckt sind die Szenarien „Kein Wintec-Gerät“, „WBT-200“, „WBT-201 mit Prüfsumme“, „Überschriebener Ringpuffer“ und „Speicher löschen“ der Spec `wintec-device`, dazu die TK1-Tests aus `wintec-file-port`.

## 2. Katalog

- [x] 2.1 `DeviceDrivers/Families/WintecDevices.swift`. Prüfen: Das Szenario „Wintec-Geräte im Katalog“ ist durch einen Test abgedeckt.

## 3. Gegenprüfung und Abschluss

- [x] 3.1 Black-Box nach D3. Das Ergebnis steht in `PROVENANCE.md`. Prüfen: Alle Tests und `openspec validate wintec-device-port --strict` sind grün.
- [ ] 3.2 [manuell, Hardware] Der Entwickler oder Anwender liest einen WBT-201 bzw. G-Rays 2 in der App aus. Prüfen: Das Ergebnis stimmt mit gpsbabel 1.7.0 (`-i wbt`) überein.
