# Proposal: main-window-sections

## Why

Das Hauptfenster stapelt heute die Kästen „Dateien“ und „Gerät“ übereinander (`App/MainWindowController.swift`).
Für Anwender, die nur eine der beiden Aufgaben haben, ist nicht sofort klar, wo sie anfangen. Der Entwickler
möchte vor der Weitergabe an Anwender eine einfach zu benutzende Oberfläche mit zwei getrennten Bereichen und hat
am 2026-11-14 den Umschalter in der Werkzeugleiste gewählt (Variante 1 der Exploration).

## What Changes

- Die Werkzeugleiste des Hauptfensters bekommt einen Umschalter „Dateien konvertieren | Gerät auslesen“; darunter
  steht jeweils nur ein Bereich.
- **Bereich „Dateien konvertieren“:** große Ablagefläche „Dateien hierher ziehen“, Knopf „Dateien auswählen …“
  und die Liste der unterstützten Formate.
- **Bereich „Gerät auslesen“:** der Gerätebereich (Gerät, Anschluss, Hinweise, Auslesen, Löschen).
- Die App merkt sich den zuletzt gewählten Bereich. Beim ersten Start ist „Gerät auslesen“ gewählt.
- Dateien, die auf das Fenster gezogen werden, schalten in jedem Bereich auf „Dateien konvertieren“ und werden
  konvertiert. „Dateien konvertieren …“ (⌘O) schaltet ebenfalls dorthin.
- Menü „Darstellung“ mit „Dateien konvertieren“ (⌘1) und „Gerät auslesen“ (⌘2).

Betroffen sind alle Geräte und Dateiformate gleichermaßen; die Treiberfamilien ändern sich nicht.

## Capabilities

### New Capabilities

(keine)

### Modified Capabilities

- `app-shell`: neue Anforderung „Bereiche des Hauptfensters“.
- `file-conversion`: „Dateien auswählen“ schaltet auf den Bereich „Dateien konvertieren“.

## Nicht im Umfang

- Neue Funktionen in den Bereichen selbst; Inhalte von Anschlusswahl und Hinweisen regelt `device-ports-and-hints`.
- Eine Seitenleiste oder weitere Bereiche (Support bleibt ein Menübefehl, Change `support-package`).
- SwiftUI; die App bleibt bei AppKit.

## Impact

- `App/MainWindowController.swift` (Werkzeugleiste, Bereiche, Drag & Drop), `App/MainMenuBuilder.swift`
  (Menü „Darstellung“), `App/ConversionPresenter.swift` (Ablagefläche), Debug-Box nur im Debug-Build in beiden
  Bereichen unten, Debug-Automation (`-DebugSection`), Lokalisierung.
