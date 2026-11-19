# Tasks: rename-and-icon

## 1. Name

- [x] 1.1 `project.yml`: `PRODUCT_NAME` und `INFOPLIST_KEY_CFBundleDisplayName` auf „myTracks Loader“ setzen (D1). `AboutWindowController` liest den Namen aus dem Bundle. Prüfen: Der Debug-Build heißt `myTracks Loader.app`, und `CFBundleIdentifier` ist weiter `info.stichling.gpsloader`.
- [x] 1.2 Texte in `App/Localizable.xcstrings`, `App/InfoPlist.xcstrings` (u. a. die Bluetooth-Begründung) und die festen Texte in GPSLoaderKit (`SupportPackageBuilder`, `SystemReport`, `RFCOMMTransport`, `CaptureFormat`) auf „myTracks Loader“ umstellen, de und en. Prüfen:
  - `Scripts/check-localizations.swift` meldet nichts.
  - Eine Suche nach „gpsloader“ in den lokalisierten Texten und im Info.plist des Builds findet nur Kennungen (Szenario „Kein alter Name sichtbar“).
- [x] 1.3 Snapshots von App-Menü, Hauptfenster und Über-Fenster auf Deutsch und Englisch mit der Debug-Automation. Prüfen: Das Szenario „App-Menü“ ist nachgewiesen, und alle Titel zeigen „myTracks Loader“.

## 2. Ablageorte und Dateien

- [x] 2.1 `AppLog`, `CaptureStore` und `SupportPackageBuilder` mit den neuen Namen (D2). Absturzberichte werden über beide Präfixe gesucht. Tests anpassen. Prüfen: Die Szenarien „Vorgeschlagener Name“ und „Rotation“ und die Suche nach Absturzberichten mit altem und neuem Präfix sind durch Tests abgedeckt.
- [x] 2.2 Übernahme alter Ordner beim Start, vor dem ersten Schreiben (D2), mit Tests in einem temporären Verzeichnis. Prüfen: Die Szenarien „Ordner mit altem Namen“ und „Beide Ordner vorhanden“ sind abgedeckt. Ein Debug-Start mit vorhandenem `~/Library/Logs/gpsloader/` hinterlässt das Protokoll in `~/Library/Logs/myTracks Loader/`.
- [x] 2.3 GPX-Creator „myTracks Loader <Version>“ (D3) mit Test. Prüfen: Das Szenario „Creator“ ist abgedeckt, und eine mit `-DebugConvert` erzeugte Datei trägt `creator="myTracks Loader 0.1.0"`.
- [x] 2.4 Prüfung, dass Einstellungen erhalten bleiben. Prüfen: Gerät, Anschluss und Bereich, die ein Build mit altem Namen gespeichert hat, erscheinen nach dem Start des neuen Builds wieder (Szenario „Einstellungen bleiben“; Snapshot).

## 3. Icon

- [x] 3.1 `Scripts/make-app-icon.swift` mit Verlauf und Satelliten-Geometrie und Vorschau-Varianten (`--variant`) (D4). Drei Varianten als PNG (1024 px) im Scratchpad erzeugen und dem Entwickler zeigen. Prüfen: Die Vorschauen liegen vor; zwei Läufe ergeben identische Dateien.
- [x] 3.2 [manuell, Entwickler] Der Entwickler wählt eine Variante und nennt gewünschte Korrekturen. Prüfen: Die Wahl ist im Design (D4) festgehalten.
- [x] 3.3 `App/AppIcon.icon` und `App/Assets.xcassets/AppIcon.appiconset` aus der gewählten Variante erzeugen. `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` setzen. Die offene Frage aus D4 klären (Rückfall-Bilder durch Xcode). Prüfen:
  - Das Bundle enthält `AppIcon.icns` bzw. `Assets.car` mit allen Größen.
  - Der Snapshot des Über-Fensters zeigt das Icon (D5).
  - Ein erneuter Lauf des Skripts ändert keine Datei im Repository.
- [x] 3.4 [manuell, Entwickler] Icon im Dock und im Finder unter macOS 27 und, falls verfügbar, unter macOS 12–15 ansehen. Prüfen: Das Icon steht nicht verkleinert in einer grauen Fläche und wirkt neben myTracks Neo stimmig.

## 4. Skripte und Dokumentation

- [x] 4.1 `Scripts/release.sh` und `Scripts/verify-bundle.sh` auf `myTracks Loader.app` und `myTracks-Loader-<Version>.zip` umstellen (D6). Prüfen: `Scripts/release.sh --skip-notarize` und `verify-bundle.sh` sind grün, und das ZIP heißt `myTracks-Loader-0.1.0.zip`.
- [x] 4.2 README (Name, Pfade der Debug-Beispiele), `CLAUDE.md` und `openspec/config.yaml` (Name statt „gpsloader (Arbeitstitel)“, Entscheidung vom 2026-11-19) anpassen. Prüfen:
  - Die Debug-Beispiele im README laufen.
  - `swift test` in GPSLoaderKit und `xcodebuild test` sind grün.
  - `openspec validate --all --strict` ist grün.

## Workflow follow-up

- Vor dem Archivieren dieses Changes `support-package` archivieren, weil dieser Change dessen Anforderungen ändert.
