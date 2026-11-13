# Tasks: gns2000-driver

## 1. Geräteschnittstelle nach GPSLoggerKit

- [x] 1.1 `DeviceProtocol.swift` nach design.md D2 nach GPSLoggerKit verschieben (MIT-Kopf), aus GPSLoggerKitGPL entfernen, `readLine` streichen. Importe in GPSLoaderKit prüfen. Prüfen: `swift test` in GPSLoggerKit, GPSLoggerKitGPL und GPSLoaderKit ist grün, und das Szenario „Gemeinsame Schnittstelle“ der Spec `logger-kit-gpl` ist durch einen Test abgedeckt.

## 2. Treiber in GPSLoggerKit

- [x] 2.1 `Devices/GNS2000/GNS2000Device.swift` nach D3, mit Kopf „eigener Code“ und Verweis auf `GNS2000.m`.
- [x] 2.2 Tests mit `GNS2000Simulator` (eigenes `SimulatedDevice` im Testziel). Prüfen: Die Szenarien „Prüfsumme eines Befehls“, „Gestörte Zeile“, „Gerät sendet NMEA“, „Gerät stumm“, „Auslesen“, „Ende fehlt“, „Umrechnung“, „Ungültiger Fix“, „Zeit springt zurück“, „Löschen bestätigt“ und „Gerät überhört den Befehl“ der Spec `gns2000-device` sind abgedeckt, ebenso „Treiber mit simuliertem Gerät“ der Spec `logger-kit`.
- [x] 2.3 `PROVENANCE.md` und `README.md` von GPSLoggerKit (Geräteschnittstelle, GNS 2000). Prüfen: Das Szenario „iOS-Build mit Treibern“ der Spec `logger-kit` ist mit einem iOS-Simulator-Build nachgewiesen.

## 3. Bluetooth-Transport und Katalog

- [x] 3.1 Modul `BluetoothTransport` mit `RFCOMMTransport` und `IOBluetoothTransportFactory` nach D4, Produkt in `Package.swift`.
- [x] 3.2 Tests der Pufferlogik ohne IOBluetooth. Prüfen: Die Szenarien „Zeilen in mehreren Paketen“ und „Gerät trennt die Verbindung“ der Spec `bluetooth-transport` sind abgedeckt.
- [x] 3.3 `DeviceConnectionKind.bluetooth`, `BluetoothTransportFactory`, `ProtocolDriver` und `Families/GNS2000Devices.swift` nach D5. Prüfen: Die Szenarien „GNS 2000 wählen“, „Bluetooth-Gerät“ und „Mitschnitt über Bluetooth“ sind durch Tests mit einer Test-Fabrik abgedeckt.

## 4. App

- [x] 4.1 `DevicePanel` und `MainWindowController` (Fabrik), `project.yml` (Produkt `BluetoothTransport`, `NSBluetoothAlwaysUsageDescription`) und `App/InfoPlist.xcstrings` (de/en) nach D6. Prüfen: Das gebaute Bundle enthält den Schlüssel in beiden Sprachen, `Scripts/check-localizations.swift` meldet nichts, und `xcodebuild test` ist grün.
- [x] 4.2 Snapshot des Gerätebereichs mit „GNS 2000“ (de/en) über die Debug-Automation. Prüfen: Es gibt keine Anschlusswahl, „Auslesen“ und „Speicher löschen …“ sind aktiv.

## 5. Dokumentation und Abschluss

- [x] 5.1 `openspec/config.yaml`: GNS 2000 in die Zuordnungsliste (GPSLoggerKit, Clean-Room, Entscheidung vom 2026-11-13), Treiber-Architektur (Geräteschnittstelle in GPSLoggerKit), offene Treiber nur noch BG728 und NAL. `docs/hardware-tests.md` um den GNS 2000 ergänzen. Prüfen: `openspec validate --all --strict` ist grün.
- [ ] 5.2 [manuell, Anwender] Ein Anwender koppelt einen GNS 2000 bzw. GNS 2000 plus, liest ihn aus und löscht ihn. Prüfen:
  - Der Berechtigungsdialog erscheint einmal.
  - Die Punkte stimmen mit myTracks bzw. der Hersteller-Software überein.
  - Nach dem Löschen ist der Speicher leer.
  - Bei Fehlern liegt ein Diagnose-Mitschnitt vor.
