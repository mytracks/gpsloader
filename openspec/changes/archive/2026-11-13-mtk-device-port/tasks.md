# Tasks: mtk-device-port

## 1. Treiber

- [x] 1.1 `MTK/MTKDevice.swift` nach design.md D1/D2 mit Dateikopf nach Regel 6.
- [x] 1.2 Tests mit `MTKSimulator`. Prüfen: Abgedeckt sind die Szenarien „NMEA-Ausgabe dazwischen“, „Kein MTK-Logger“, „Auslesen“, „Belegung unbekannt“, „Abgelehnter Block“, „Holux M-241“ und „Speicher löschen“ der Spec `mtk-device`.

## 2. Katalog

- [x] 2.1 `DeviceDrivers/Families/MTKDevices.swift`. Prüfen: Das Szenario „MTK-Geräte im Katalog“ ist durch einen Test abgedeckt.

## 3. Gegenprüfung und Abschluss

- [x] 3.1 Black-Box nach D3. Das Ergebnis steht in `PROVENANCE.md`. Prüfen: Alle Tests und `openspec validate mtk-device-port --strict` sind grün.
- [ ] 3.2 [manuell, Hardware] Der Entwickler liest einen MTK-Logger (z. B. Qstarz) und einen Holux M-241 in der App aus und löscht sie. Prüfen: Die Ergebnisse stimmen mit gpsbabel 1.7.0 überein, und das Logging läuft danach weiter.
