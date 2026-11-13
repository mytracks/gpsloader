# Design: Dateien nach GPX konvertieren

## Context

- Die App ist eine AppKit-App ohne Nib (`App/MainMenuBuilder.swift`, `App/MainWindowController.swift`). Lesevorgänge von Loggern laufen über `SessionPresenter` mit `ProgressSheetController` (Kindfenster statt Sheet, damit Beenden nicht blockiert) und `GPXExport.write`.
- GPSLoggerKit bietet `FileFormats.all`, `FileFormats.detect(prefix:fileName:)`, `FileFormats.read(_:format:options:)` (async, abbrechbar), `FileInput.load(_:)` (speichergemappt), `RecordingProcessing` und lokalisierte `GPSLoggerError`/`ImportWarning`.
- Die Alt-App konvertierte Dateien mit gpsbabel (`MyTracksMainController.m`, `convertNMEAFile:` ca. Zeile 1883–1934; `GPSBabel.m`, Dateimodus) und hängte NMEA-Dateien vorher per `cat` aneinander. Danach folgten Wochenüberlauf-Korrektur und Wegpunkte-als-Track (`docs/legacy-analysis.md`, Abschnitt 4 und 5). Diese Abläufe werden nicht portiert, sondern durch GPSLoggerKit ersetzt.

## Goals / Non-Goals

**Goals:**
- Dünne UI über einer testbaren Konvertierungslogik.
- Kein gpsbabel, kein Rosetta, kein Main-Actor-Blockieren auch bei 50-MB-Dateien.
- Neue GPSLoggerKit-Formate ohne App-Änderung.

**Non-Goals:** siehe Proposal, „Nicht im Umfang“.

## Decisions

### D1 Modul `FileConversion` in GPSLoaderKit

Neues Ziel `FileConversion`, nur abhängig von `GPSLoggerKit`, mit Testziel `FileConversionTests`. Öffentliche API:

```swift
public struct ConversionPlan: Sendable {
    public struct Group: Sendable { public let formatID: FileFormatID; public let inputs: [FileInput] }
    public let groups: [Group]           // in order of first occurrence
    public let unrecognized: [String]    // file names
    public var isEmpty: Bool
    public func excludingUnrecognized() -> ConversionPlan
}

public enum FileConverter {
    /// Loads the files (memory mapped) and detects their formats. Throws GPSLoggerError(.unreadable / .empty).
    public static func plan(for urls: [URL]) throws -> ConversionPlan
    /// Reads all groups, merges and post-processes. Cancellable.
    public static func convert(_ plan: ConversionPlan, referenceDate: Date = Date()) async throws -> ImportResult
    /// "<first file name without extension>.gpx"
    public static func suggestedFileName(for urls: [URL]) -> String
}
```

Warum nicht in GPSLoggerKit: Gruppieren mehrerer Formate und die App-Voreinstellungen sind App-Verhalten; GPSLoggerKit bleibt beim Ein-Format-Vertrag. Warum nicht direkt in der App: Die App hat kein Testziel für Logik; die Regeln der Spec sollen ohne UI geprüft werden.

### D2 Erkennung und leere Dateien

`plan` lädt jede Datei mit `FileInput.load` und ruft `FileFormats.detect(prefix:fileName:)` mit den ersten 4096 Bytes. Eine leere Datei würde sonst als „nicht unterstützt“ erscheinen; sie führt deshalb zu `GPSLoggerError(.empty)`, damit die Meldung stimmt. Nicht lesbare Dateien werfen `.unreadable`. Erkannte Dateien werden nach Format-ID gruppiert, die Reihenfolge innerhalb einer Gruppe ist die Auswahlreihenfolge.

### D3 Zusammenführen und Nachbearbeitung

`convert` liest jede Gruppe mit `FileFormats.read(group.inputs, format:, options:)` und `ImportOptions(correctWeekRollover: true, referenceDate:, waypointsAsTrackWhenNoTracks: false)`. Danach: Tracks und Wegpunkte in Gruppenreihenfolge aneinanderhängen, Warnungen ebenso. Erst auf dem Gesamtergebnis wird `RecordingProcessing.waypointsAsTrack` angewendet, falls es keine Tracks enthält. So macht eine GPX-Datei mit Wegpunkten neben einer IGC-Datei mit Track keinen zusätzlichen Track. Ist das Gesamtergebnis leer, wirft `convert` `GPSLoggerError(.noUsableData)` mit dem Namen der ersten Datei. (Einzelne Gruppen ohne Daten werfen bereits in `FileFormats.read`; das ist gewollt, die Spec verlangt bei unbrauchbaren Dateien eine Meldung und kein Speichern.)

### D4 Nebenläufigkeit und Abbruch

- `ConversionPresenter` (neu, `App/ConversionPresenter.swift`) ist `@MainActor`. Er startet einen `Task.detached(priority: .userInitiated)`, der `plan` und `convert` ausführt. Dateizugriff und Parsen laufen damit nicht auf dem Main Actor.
- Alle übergebenen Typen (`URL`, `ConversionPlan`, `ImportResult`) sind `Sendable`.
- „Abbrechen“ im `ProgressSheetController` ruft `task.cancel()`. GPSLoggerKit prüft den Abbruch kooperativ (alle 4096 Zeilen bzw. Elemente) und wirft `CancellationError`; der Presenter schließt dann still das Fortschrittsfenster. Die 1-Sekunden-Grenze ist in GPSLoggerKit bereits für NMEA, GPX und IGC getestet.
- Ein Zeitlimit ist nicht nötig: Dateien enden immer.
- `isConverting` verhindert eine zweite Konvertierung; Menüeintrag (`validateMenuItem`), Schaltfläche und Drop-Ziel fragen es ab. Läuft gleichzeitig eine Logger-Sitzung, ist das erlaubt, weil keine gemeinsame Ressource betroffen ist.
- Beim Beenden der App bricht `AppDelegate.applicationShouldTerminate` auch eine laufende Konvertierung ab (kein gpsbabel-Prozess, also kein Warten nötig).

### D5 Benutzeroberfläche

- Menü „Ablage“ zwischen App- und Bearbeiten-Menü mit „Dateien konvertieren…“ (⌘O). Ziel ist der `ConversionPresenter` des Hauptfensters über die Responder-Kette (`MainWindowController` implementiert die Aktion).
- Hauptfenster: neuer Bereich „Dateien“ über „Gerät“ mit kurzem Erklärtext („NMEA, GPX, IGC …“, aus `FileFormats.all.map(\.displayName)` gebildet) und Schaltfläche „Dateien konvertieren…“.
- Drag & Drop: Die Inhaltsansicht wird eine `FileDropView` (NSView-Unterklasse), registriert für `.fileURL`. Sie nimmt nur reguläre Dateien an (`isRegularFile`), keine Ordner, und nur, wenn keine Konvertierung läuft.
- `NSOpenPanel`: `allowsMultipleSelection = true`, `canChooseDirectories = false`, keine Typbeschränkung (Spec „Unterstützte Formate“: die Endung ist nur ein Hinweis).
- Nicht erkannte Dateien: `NSAlert` mit der Liste und den Knöpfen „Ohne diese Dateien fortfahren“ / „Abbrechen“; sind alle unbekannt, nur eine Meldung.
- `NSSavePanel` mit `FileConverter.suggestedFileName` und dem Ordner der ersten Datei als `directoryURL`. Schreiben über `GPXExport.write` mit `AppEnvironment.shared.gpxCreator`, Fehler wie bisher über `SessionPresenter.showError`.
- Fehler aus GPSLoggerKit: `NSAlert` mit `errorDescription` als Titel und `failureReason` als „Details: …“.
- Warnungen nach dem Speichern: ein `NSAlert` (informativ) mit `warning.message()` je Zeile.

### D6 Testbarkeit der App

`DebugAutomation` erhält `-DebugConvert <Pfad>[,<Pfad>…]`. Zusammen mit dem vorhandenen `-DebugSaveDirectory` schreibt die App ohne Sicherungsdialog, und mit `-DebugSnapshotDirectory` lassen sich Hauptfenster, Meldungen und Fortschrittsfenster prüfen. Der Sicherungsdialog läuft außerhalb des Prozesses und ist so nicht automatisierbar; er wird manuell geprüft.

## Risks / Trade-offs

- [Sehr viele oder sehr große Dateien] → Dateien werden speichergemappt geladen; der Speicherbedarf entspricht dem von GPSLoggerKit gemessenen (ca. 130 MB bei 52 MB NMEA).
- [Ergebnis verschiedener Formate in einer Datei kann überraschen] → Entspricht der Spec; getrennte Dateien sind ausdrücklich nicht im Umfang.
- [Fehler in einer von mehreren Dateien bricht alles ab] → Bewusst: lieber eine klare Meldung als eine stillschweigend unvollständige GPX-Datei.

## Migration Plan

Keine. Neues Verhalten, `GPSLoaderKit`-Produkte bleiben unverändert.

## Open Questions

Keine.
