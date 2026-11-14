# Tasks: device-ports-and-hints

## 1. SerialTransport

- [x] 1.1 `SerialPortKind` und `usbLocationID` in `SerialPortInfo`, Einordnung als statische Funktion (D1). Tests mit Eigenschaften wie auf macOS 27 beobachtet. Prüfen: Die Szenarien „Gekoppeltes Bluetooth-Gerät“ und „Systemanschluss“ der Spec `serial-transport` sind abgedeckt.
- [x] 1.2 `USBDeviceCatalog.changes()` (D5); die Liste selbst kommt aus Change `support-package`. Prüfen: Das Szenario „Adapter ohne Treiber“ ist durch einen Test der Zuordnung abgedeckt.

## 2. DeviceDrivers

- [x] 2.1 `USBSerialChip` mit Treiberseiten (D2) und `PortPresentation` (D3) mit Tests. Prüfen: Die Szenarien „Passender Bluetooth-Anschluss“ und „Systemanschlüsse“ der Spec `device-mode` sind abgedeckt.
- [x] 2.2 `DeviceHint`, Einträge für M-241, GNS 2000 und i-GotU, `DeviceSelection.hints` (D4, D5) mit Tests. Prüfen: Die Szenarien „M-241 über Bluetooth“, „Treiber fehlt“ und „Treiber vorhanden“ sind abgedeckt, „Kein Anschluss“ weiterhin.

## 3. App

- [x] 3.1 `DevicePanel`: Titel, Tooltip, Hinweisbereich mit Links, USB-Beobachtung; `SessionPresenter`: Hinweis bei Zeitüberschreitung (D6). Lokalisierung de/en. Prüfen: Snapshots (de/en) mit M-241 und Bluetooth-Anschluss (pty-Simulator mit Bluetooth-Namen ist nicht möglich, daher Test mit eingespeister Anschlussliste über die Debug-Automation); das Szenario „Fehlschlag über Bluetooth“ ist durch einen Test abgedeckt; `Scripts/check-localizations.swift` meldet nichts.

## 4. Abschluss

- [x] 4.1 README und `docs/hardware-tests.md` (Hinweise prüfen), `swift test` in GPSLoaderKit und `xcodebuild test` grün, `openspec validate --all --strict` grün.
- [ ] 4.2 [manuell, Hardware] Der Entwickler steckt den Holux M-241 per USB an und koppelt ihn per Bluetooth. Prüfen: Beide Anschlüsse haben sprechende Namen, der Bluetooth-Hinweis erscheint, und die vier Treiberseiten öffnen sich im Browser.
