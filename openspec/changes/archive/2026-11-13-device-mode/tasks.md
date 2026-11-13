# Tasks: device-mode

## 1. GPL-Paket

- [x] 1.1 `Device/DeviceProtocol.swift` nach design.md D1, dazu der Test-Helfer `SimulatedDevice`. Prüfen: Ein Test-Protokoll liest über `SimulatedDevice` eine Aufzeichnung (Szenario „Simuliertes Gerät“), und ein Zeitlimit kommt als Fehler an.

## 2. GPSLoaderKit

- [x] 2.1 `SerialPort.setBaudRate(_:)` und `discardInput()` nach D3. Prüfen: Ein Test mit einem Pseudo-Terminal stellt die Rate um, und `tcgetattr` zeigt die neue Rate (Szenario „Wechsel nach der Verhandlung“). Eine nicht unterstützte Rate wird abgelehnt.
- [x] 2.2 Modul `DeviceDrivers` nach D2: `DeviceEntry`, `DeviceCatalog`, `ProtocolDriver` und `ConnectionBridge`. Prüfen: Tests mit `MockTransport` decken die Szenarien „Protokollfehler“ und „Mitschnitt“ ab und zeigen, dass Fortschritt ankommt und der Transport auch bei Fehlern geschlossen wird.

## 3. App

- [x] 3.1 `DevicePanel` nach D4, eingebunden in `MainWindowController`, mit Lokalisierung (de, en). Dazu kommt das Produkt `DeviceDrivers` in `project.yml`. Prüfen: Die Szenarien „Auswahl merken“, „Logger angesteckt“, „Kein Anschluss“, „Gerät ohne Löschfunktion“ und „Treiber fehlt“ sind durch Snapshots bzw. Tests der Auswahl-Logik abgedeckt. Der Lokalisierungstest ist grün.

## 4. Abschluss

- [x] 4.1 Prüfen, dass alles grün ist: alle Paket-Tests, `xcodebuild test` und `openspec validate device-mode --strict`.
