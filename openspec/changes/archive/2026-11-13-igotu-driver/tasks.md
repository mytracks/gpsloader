# Tasks: igotu-driver

## 1. Treiber

- [x] 1.1 `IGotU/IGotUDevice.swift` nach design.md D1/D3 mit Dateikopf nach Regel 6.
- [x] 1.2 Tests mit `IGotUSimulator`. Prüfen: Abgedeckt sind die Szenarien „Gerätefehler“, „GT-800 auslesen“, „USB-Modell auslesen“, „Jahr modulo 16“, „Wenige Satelliten“, „Speicher löschen (experimentell)“ und „Modell ohne Löschfunktion“ der Spec `igotu-device`.
- [x] 1.3 `credits` um igotu2gpx ergänzen. Prüfen: Das Szenario „Credits mit igotu2gpx“ der Spec `logger-kit-gpl` ist durch einen Test abgedeckt.

## 2. HID und Katalog

- [x] 2.1 Modul `HIDTransport` nach D2, eingebunden in App und `project.yml`. Prüfen: Das Szenario „Kein i-GotU angeschlossen“ ist durch einen Test abgedeckt.
- [x] 2.2 `DeviceDrivers/Families/IGotUDevices.swift`. Prüfen: Das Szenario „i-GotU-Geräte im Katalog“ ist durch Tests abgedeckt (keine Portwahl über `needsPort`).
- [x] 2.3 Ende-zu-Ende-Test: Die App liest einen simulierten GT-800 am Pseudo-Terminal. Prüfen: Alle Tests und `openspec validate igotu-driver --strict` sind grün.

## 3. Manuell

- [x] 3.1 [manuell] Der Entwickler entscheidet über den offenen Vorschlag „i-GotU-Löschen experimentell“ (Proposal) und trägt das Ergebnis in `openspec/config.yaml` ein.
- [ ] 3.2 [manuell, Anwender] Anwender lesen einen GT-800 und ein USB-Modell (z. B. GT-120) in der App aus. Prüfen: Das USB-Modell wird gefunden (HID), und die Punkte stimmen mit @trip PC bzw. igotu2gpx überein.
- [ ] 3.3 [manuell, Anwender] Anwender testen das Löschen experimentell. Prüfen: Danach meldet das Gerät 0 Datensätze.
