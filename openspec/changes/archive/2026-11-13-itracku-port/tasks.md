# Tasks: itracku-port

## 1. Treiber und Katalog

- [x] 1.1 `ITrackU/ITrackUDevice.swift` nach design.md D1–D3, mit Dateikopf nach den Regeln des GPL-Pakets.
- [x] 1.2 Tests mit `ITrackUSimulator`. Prüfen: Die Szenarien „Gerät antwortet“, „Anderes Gerät“, „Speicher mit Endemarke“, „Gerät verstummt“, „Umrechnung“ und „Leerer Speicherplatz“ der Spec `itracku-device` sind abgedeckt.
- [x] 1.3 `DeviceDrivers/Families/ITrackUDevices.swift` und `DeviceCatalogContent`. Prüfen: Das Szenario „iTrackU wählen“ ist durch einen Test abgedeckt.
- [x] 1.4 `credits` (Andreas Grimme), `PROVENANCE.md` und `README.md` des Pakets. Außerdem `openspec/config.yaml`: iTrackU aus „Weiterhin über gpsbabel“ in die Zuordnungsliste des GPL-Pakets (Change `itracku-port`).

## 2. Gegenprüfung und Abschluss

- [x] 2.1 Black-Box nach D5. Prüfen: Das Ergebnis steht in `PROVENANCE.md`, und alle Tests sowie `openspec validate itracku-port --strict` sind grün.
- [ ] 2.2 [manuell, Anwender] Ein Anwender liest einen XAiOX iTrackU über Bluetooth oder USB in der App aus. Prüfen: Die Punkte stimmen mit gpsbabel 1.7.0 (`-t -i itracku`) überein, im Zweifel mit Diagnose-Mitschnitt.
