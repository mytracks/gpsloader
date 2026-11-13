# Tasks: file-conversion

## 1. Modul FileConversion

- [x] 1.1 Ziel `FileConversion` und Testziel `FileConversionTests` in `Packages/GPSLoaderKit/Package.swift` anlegen (design.md D1), abhängig nur von `GPSLoggerKit`. Prüfen: `swift build --package-path Packages/GPSLoaderKit` ohne Warnungen.
- [x] 1.2 `ConversionPlan` und `FileConverter.plan(for:)` nach design.md D1/D2: laden, erkennen, nach Format gruppieren, unbekannte Dateien sammeln, leere und unlesbare Dateien als Fehler.
- [x] 1.3 Tests zu 1.2 mit Dateien im temporären Verzeichnis. Prüfen: Szenarien „NMEA mit Endung .LOG“, „Eine von drei Dateien unbekannt“, „Nur unbekannte Dateien“; Reihenfolge der Gruppen und innerhalb der Gruppen; leere Datei ergibt `.empty`, fehlende Datei `.unreadable`; `excludingUnrecognized()`.
- [x] 1.4 `FileConverter.convert` und `suggestedFileName(for:)` nach design.md D3.
- [x] 1.5 Tests zu 1.4. Prüfen: Szenarien „Zwei NMEA-Dateien“, „Gemischte Formate“, „Nur Wegpunkte“, „Alter Logger mit Wochenüberlauf“, „Name vorschlagen“, „Keine Positionen“, „Kaputte GPX-Datei“; Warnungen mehrerer Gruppen bleiben erhalten; Wegpunkte neben einem Track werden nicht zum Track; Abbruch einer großen NMEA-Datei endet in weniger als einer Sekunde mit `CancellationError`.

## 2. App

- [x] 2.1 `project.yml`: Produkt `FileConversion` für die App, `FileConversionTests` im Test-Schema; `xcodegen generate`. Prüfen: Die App baut.
- [x] 2.2 `ConversionPresenter` nach design.md D4/D5: Ablauf Auswahl → Plan → Nachfrage bei unbekannten Dateien → Fortschritt → Speichern → Warnungen; Abbruch; `isConverting`; Abbruch beim Beenden der App im `AppDelegate`.
- [x] 2.3 Menü „Ablage“ mit „Dateien konvertieren…“ (⌘O) und Menüvalidierung; Bereich „Dateien“ mit Schaltfläche im Hauptfenster; `FileDropView` für Drag & Drop (nur reguläre Dateien, nicht während einer Konvertierung).
- [x] 2.4 Alle neuen Texte in `App/Localizable.xcstrings` auf Deutsch und Englisch. Prüfen: `check-localizations` meldet keine fehlenden Übersetzungen.
- [x] 2.5 `DebugAutomation`: `-DebugConvert` nach design.md D6.
- [x] 2.6 Automatischer App-Test mit `-DebugConvert`, `-DebugSaveDirectory` und `-DebugSnapshotDirectory` über die Fixtures von GPSLoggerKit. Prüfen:
  - NMEA + IGC ergibt eine GPX-Datei, die mit `xmllint --schema` gültig ist und beide Tracks enthält.
  - Eine Datei mit Prüfsummenfehlern zeigt nach dem Speichern die Warnung (Snapshot).
  - Eine unbekannte Datei zeigt die Nachfrage (Snapshot), eine kaputte GPX-Datei die Fehlermeldung mit Zeile (Snapshot).
  - Das Hauptfenster zeigt den Bereich „Dateien“ (Snapshot, Deutsch und Englisch).
  - Mit `-DebugCancelAfter` bricht eine 50-MB-NMEA-Datei ab, ohne Datei und ohne Meldung.

## 3. Abschluss

- [x] 3.1 Alle Tests: `swift test` für GPSLoaderKit und GPSLoggerKit, `xcodebuild test` für die App. Prüfen: grün.
- [x] 3.2 README (Abschnitt Bedienung/Struktur) um den Dateimodus und `FileConversion` ergänzen; `openspec validate file-conversion --strict`. Prüfen: gültig.
- [ ] 3.3 [manuell, Hardware] Der Entwickler prüft die Bedienung am Mac: Dateidialog mit Mehrfachauswahl, Drag & Drop aus dem Finder, Sicherungsdialog mit vorgeschlagenem Namen und Ordner, ⌘O, Abbrechen. Dazu echte Dateien eigener Geräte (z. B. Sony CS-1, Garmin, IGC) konvertieren und das Ergebnis in myTracks öffnen. Prüfen: Ablauf wie in der Spec, Tracks vollständig.
