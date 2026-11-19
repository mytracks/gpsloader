# Tasks: main-window-sections

## 1. Fenster

- [x] 1.1 Werkzeugleiste mit Umschalter, `NSTabView` mit beiden Bereichen, `MainWindowSection` mit Speicherung (D1, D2). Prüfen: Die Szenarien „Erster Start“ und „Bereich merken“ der Spec `app-shell` sind mit der Debug-Automation (Snapshots nach Neustart) nachgewiesen.
- [x] 1.2 Menü „Darstellung“ mit ⌘1/⌘2; ⌘O und Drag & Drop schalten auf „Dateien konvertieren“ (D2). Prüfen: Die Szenarien „Tastenkürzel“ und „Drag & Drop im Gerätebereich“ sind nachgewiesen (Debug-Automation mit `-DebugSection device -DebugConvert …`).
- [x] 1.3 Ablagefläche im Bereich „Dateien konvertieren“ (D3) und Debug-Box (D4). Lokalisierung de/en. Prüfen: Snapshots (de/en) beider Bereiche; `Scripts/check-localizations.swift` meldet nichts.

## 2. Abschluss

- [x] 2.1 README (Bedienung) aktualisieren; `xcodebuild test` grün; `openspec validate --all --strict` grün.
- [x] 2.2 [manuell, Hardware] Der Entwickler prüft die Bedienung auf seinem Mac: Umschalter, ⌘1/⌘2, Drag & Drop aus dem Finder in beiden Bereichen, Ablagefläche anklicken. Prüfen: Ablauf wie in den Specs.
