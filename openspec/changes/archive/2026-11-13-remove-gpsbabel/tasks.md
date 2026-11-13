# Tasks: remove-gpsbabel

## 0. Voraussetzung

- [x] 0.1 `magellan-port`, `itracku-port` und `alan-port` sind umgesetzt. Prüfen: In `openspec/config.yaml` steht unter „Weiterhin über gpsbabel“ keine Familie mehr.

## 1. GPSLoaderKit

- [x] 1.1 Modul `GPSBabelRuntime` und `GPSBabelRuntimeTests` entfernen, `Package.swift` anpassen (design.md D1).
- [x] 1.2 `LoggerCore`: `rosettaMissing`, `gpsbabelFailed`, `ProcessRecord` und `DiagnosticEvent.process` samt Texten entfernen. `DiagnosticCapture` anpassen. Tests: Prüfen, dass das Szenario „App unter Rosetta“ der Spec `diagnostic-capture` und das Szenario „Protokollfehler“ der Spec `logger-session` abgedeckt sind.
- [x] 1.3 `Vendor/Licenses/GPL-3.0.txt` anlegen und `AppFormatsTests.gplLicenseFilesMatch` umstellen (D2). Prüfen: `swift test` in GPSLoaderKit ist grün.

## 2. App und Projekt

- [x] 2.1 App: `RosettaInstallation.swift` und `EnvironmentStatusView` entfernen. Außerdem den Laufzeitstatus in `AppEnvironment`, das Statusmenü und `-DebugSimulatedStatus` in der Debug-Automation und den Demo-Fall `childProcess`.
- [x] 2.2 `AppDelegate` nach D3 und `AboutWindowController` nach D4 anpassen. In `Localizable.xcstrings` die verwaisten Texte entfernen. Prüfen: `Scripts/check-localizations.swift` meldet nichts.
- [x] 2.3 `project.yml` (D1, D2), dann `RosettaInstaller/`, `Scripts/sign-helpers.sh` und `Vendor/gpsbabel-1.7.0` entfernen und xcodegen ausführen.
- [x] 2.4 `Scripts/verify-bundle.sh` nach D5. Prüfen:
  - `xcodebuild test` ist grün.
  - `verify-bundle.sh` ist für einen Debug-Build grün.
  - Das Bundle enthält kein `Contents/Helpers`.
  - Das Szenario „Lizenztexte im Bundle“ der Spec `app-shell` ist erfüllt.

## 3. Dokumentation und Abschluss

- [x] 3.1 `openspec/config.yaml`, `CLAUDE.md`, `README.md` und `Packages/GPSLoggerKitGPL/README.md` nach D6/D7. Prüfen: `openspec validate --all --strict` ist grün.
- [x] 3.2 Snapshot von Hauptfenster und Über-Fenster (de/en) über die Debug-Automation. Prüfen: Die Szenarien „Über-Fenster öffnen“ und „Portierte Formate“ der Spec `app-shell` sind erfüllt, und das Hauptfenster zeigt keinen Bereich „Umgebung“.
- [ ] 3.3 [manuell, Hardware] Der Entwickler startet einen Release-Build auf einem Apple-Silicon-Mac ohne Rosetta und auf einem Intel-Mac. Prüfen: Die App startet ohne Rosetta-Dialog, Dateimodus und Direktmodus funktionieren.
