# Design: main-window-sections

## Context

- `MainWindowController.buildContent()` legt zwei `NSBox` („Dateien“, „Gerät“) und im Debug-Build eine Debug-Box in
  einen `NSStackView` innerhalb von `FileDropView` (Drag & Drop für das ganze Fenster).
- `MainMenuBuilder` baut die Menüs App, Ablage, Bearbeiten, Fenster (und bis Change `support-package` Diagnose).
- Mindestsystem macOS 12; die App ist reines AppKit ohne SwiftUI.

## Goals / Non-Goals

**Goals:**
- Werkzeugleiste und Bereiche mit AppKit-Bordmitteln, die auf macOS 12 bis 27 gleich aussehen.
- Der Wechsel des Bereichs ist ohne UI-Test über die Debug-Automation prüfbar.

**Non-Goals:**
- Kein Umbau von `DevicePanel` und `ConversionPresenter` über die Ablagefläche hinaus.

## Decisions

### D1 Umschalter als `NSToolbarItemGroup`

`NSToolbarItemGroup(itemIdentifier:titles:selectionMode: .selectOne, labels:target:action:)` (ab macOS 10.15),
zentriert über `toolbar.centeredItemIdentifier` (ab macOS 13; auf macOS 12 links neben flexiblem Raum),
`window.toolbarStyle = .unified`. Alternative `NSSegmentedControl` als `view` eines `NSToolbarItem` –
verworfen, weil die Gruppe Beschriftungen im Überlaufmenü und die Darstellung im Textmodus mitbringt.

### D2 Bereiche als `NSTabView` ohne Reiter

`NSTabView` mit `tabViewType = .noTabsNoBorder` und zwei `NSTabViewItem`; ein `MainWindowSection`-Enum
(`files`, `device`) mit `rawValue` für `UserDefaults` (Schlüssel `MainWindowSection`). `select(_ section:)`
setzt Tab, Umschalter und Defaults; Menübefehle `showFilesSection(_:)` / `showDeviceSection(_:)` mit Häkchen
über `validateMenuItem`. `FileDropView` bleibt Inhalt des Fensters und umschließt die `NSTabView`, sodass
Drag & Drop in beiden Bereichen funktioniert; `onDrop` ruft erst `select(.files)`.

### D3 Bereich „Dateien konvertieren“

Oben eine `DropZoneView` (gestrichelter Rahmen, Symbol `square.and.arrow.down` ab macOS 11 über
`NSImage(systemSymbolName:)`, Text „Dateien hierher ziehen“) mit hervorgehobenem Rahmen während des Ziehens
(Rückmeldung von `FileDropView` über eine Closure), darunter „Dateien auswählen …“ und die Formatliste als
umbrechender Sekundärtext. Ein Klick auf die Ablagefläche öffnet ebenfalls den Dateidialog.

### D4 Debug-Box

Im Debug-Build unterhalb beider Bereiche (außerhalb der `NSTabView`), damit Demo-Treiber in beiden Bereichen
erreichbar bleiben. Neues Startargument `-DebugSection files|device`.

## Risks / Trade-offs

- [`centeredItemIdentifier` fehlt auf macOS 12] → Gruppe dort links; rein optisch.
- [Neue Fenstermindestgröße durch die Ablagefläche] → `minSize` bleibt 520×360; die Ablagefläche passt sich an.
