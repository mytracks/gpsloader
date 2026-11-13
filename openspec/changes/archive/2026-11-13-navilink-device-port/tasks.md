# Tasks: navilink-device-port

## 1. Treiber und Katalog

- [x] 1.1 `Locosys/NavilinkDevice.swift` nach design.md D1/D2 mit Dateikopf nach Regel 6.
- [x] 1.2 Tests mit `NavilinkSimulator`. Prüfen: Abgedeckt sind die Szenarien „Nicht im NAVILINK-Modus“, „Prüfsummenfehler“ und „Auslesen“ der Spec `navilink-device`.
- [x] 1.3 `DeviceDrivers/Families/NavilinkDevices.swift`. Prüfen: Das Szenario „Navilink-Geräte im Katalog“ ist durch einen Test abgedeckt.

## 2. Gegenprüfung und Abschluss

- [x] 2.1 Black-Box nach D3. Das Ergebnis steht in `PROVENANCE.md`. Prüfen: Alle Tests und `openspec validate navilink-device-port --strict` sind grün.
- [ ] 2.2 [manuell, Anwender] Ein Anwender liest einen Locosys GT-31 im NAVILINK-Modus in der App aus. Prüfen: Wegpunkte und Track stimmen mit gpsbabel 1.7.0 (`-i navilink`) überein.
