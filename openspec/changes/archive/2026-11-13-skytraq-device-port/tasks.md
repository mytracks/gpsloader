# Tasks: skytraq-device-port

## 1. Treiber

- [x] 1.1 `SkyTraq/SkyTraqDevice.swift` nach design.md D1/D2 mit Dateikopf nach Regel 6, dazu `SkyTraqDump.usedLength(ofSector:)` und die Endregel des Downloads in `SkyTraqDump.read`.
- [x] 1.2 Tests mit `SkyTraqSimulator`. Prüfen: Die Szenarien „Prüfsummenfehler“, „Bekannte Baudrate“, „Kein Logger“, „Auslesen“, „Einzelne Sektoren“ und „Speicher löschen“ der Spec `skytraq-device` sind abgedeckt.

## 2. Katalog

- [x] 2.1 `DeviceDrivers/Families/SkyTraqDevices.swift` mit den elf Geräten. Prüfen: Das Szenario „Geräte im Katalog“ ist durch einen Test abgedeckt.

## 3. Gegenprüfung und Abschluss

- [x] 3.1 Black-Box nach D3. Prüfen: gpsbabel und die App lesen aus dem Python-Simulator dieselben 517 Punkte. Positionen, Höhen und Zeiten stimmen überein, das Ergebnis steht in `PROVENANCE.md`. Alle Tests und `openspec validate skytraq-device-port --strict` sind grün.
- [ ] 3.2 [manuell, Hardware] Der Entwickler liest einen SkyTraq-Logger in der App aus und löscht ihn. Prüfen: Punktanzahl und Zeiten stimmen mit gpsbabel 1.7.0 (`-i skytraq`) überein, und nach dem Löschen ist der Logger leer.
