# Tasks: support-package

## 1. Mitschnitt immer aktiv

- [x] 1.1 `CaptureStore` ohne Schalter, `AppEnvironment.makeRecorder()` immer, `SessionPresenter` angepasst (D6). Prüfen: Die Szenarien „Erster Start“ und „Fehlgeschlagener Vorgang“ der Spec `diagnostic-capture` sind durch Tests abgedeckt.

## 2. Modul SupportPackage

- [x] 2.1 `AppLog` mit Rotation (D2) und Tests. Prüfen: Das Szenario „Rotation“ ist abgedeckt.
- [x] 2.2 `SystemReport`, `USBDeviceCatalog` (SerialTransport), Einstellungen und Absturzberichte (D3) mit Tests der Textausgabe. Prüfen: Das Szenario „Keine Seriennummern“ ist abgedeckt.
- [x] 2.3 `SupportPackageBuilder` mit ZIP über `NSFileCoordinator` (D4, D5). Tests mit festen Quellen lesen das Inhaltsverzeichnis des ZIP. Prüfen: Die Szenarien „Vollständiges Paket“ und „Inhalt abgewählt“ sind abgedeckt.
- [x] 2.4 `PairedBluetoothDevices.listIfAuthorized()` in `BluetoothTransport`: ohne Berechtigung `nil`, ohne IOBluetooth-Aufruf. Prüfen: Der Code ruft IOBluetooth nur nach der Prüfung von `CBManager.authorization` auf.

## 3. App

- [x] 3.1 Protokolleinträge in `AppDelegate`, `DevicePanel`, `SessionPresenter`, `ConversionPresenter` (D2). Prüfen: Das Szenario „Fehlgeschlagener Vorgang“ der Spec `support-package` ist mit der Debug-Automation (Demo-Treiber) nachgewiesen.
- [x] 3.2 `SupportPackageController`, Menü „Hilfe“, Knopf in der Fehlermeldung, Menü „Diagnose“ entfernt, Debug-Automation (D7). Lokalisierung de/en. Prüfen: Snapshots (de/en) des Sheets; `-DebugSupportPackagePath` erzeugt ein ZIP mit allen Teilen; „Ohne Bluetooth-Berechtigung“ zeigt keinen Dialog; `Scripts/check-localizations.swift` meldet nichts.

## 4. Abschluss

- [x] 4.1 README (Abschnitt Support), `docs/hardware-tests.md` (Hinweis: bei Fehlern Support-Paket statt Mitschnitt), `openspec/config.yaml` (Diagnose-Mitschnitt immer aktiv, Entscheidung vom 2026-11-14). Prüfen: `swift test` in GPSLoaderKit und `xcodebuild test` sind grün, `openspec validate --all --strict` ist grün.
- [ ] 4.2 [manuell, Hardware] Der Entwickler erstellt nach einem echten Auslesen (z. B. Holux M-241) ein Support-Paket. Prüfen: Das ZIP lässt sich im Finder öffnen, und die Inhalte sind vollständig und lesbar.
