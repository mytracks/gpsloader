# Proposal: support-package

## Why

gpsloader soll an Anwender gehen, deren Logger der Entwickler nicht hat (Bluetooth-Logger, i-GotU, iTrackU,
GNS 2000, siehe `docs/hardware-tests.md`). Heute muss ein Anwender den Diagnose-Mitschnitt vorher von Hand
einschalten und kann danach nur den Mitschnitt des letzten Vorgangs sichern. Merkt er erst nach einem Fehler,
dass er einen Mitschnitt braucht, muss er den Vorgang wiederholen; Angaben zu System, Anschlüssen und
Ablauf fehlen ganz. In der Exploration vom 2026-11-14 hat der Entwickler entschieden: Der Mitschnitt läuft
immer mit, und die App stellt alles Nötige als ein ZIP bereit, das der Anwender selbst verschickt (keine Mail).

## What Changes

- **Mitschnitt immer aktiv:** Jeder Lese- und Löschvorgang wird aufgezeichnet, lokal, wie bisher höchstens die
  letzten 10 Vorgänge. Der Schalter „Diagnose-Mitschnitt aufzeichnen“ entfällt.
- **App-Protokoll:** Die App schreibt ein rotierendes Protokoll unter `~/Library/Logs/gpsloader/` (Start,
  Anschlüsse, Geräte- und Anschlusswahl, Vorgänge mit Ergebnis, Fehler mit Detailtext; keine Positionen,
  keine Dateinamen), höchstens etwa 5 MB.
- **Support-Paket:** Der Befehl „Support-Paket erstellen …“ (Menü „Hilfe“ und in jeder Fehlermeldung eines
  Vorgangs) zeigt die Inhalte mit Häkchen und sichert danach ein ZIP:
  - System- und App-Informationen (Version, Build, macOS, Mac-Modell, Architektur, Rosetta, Sprache, Zeitzone)
  - App-Protokoll und Einstellungen der App
  - serielle Anschlüsse und USB-Geräte mit Hersteller- und Produkt-ID, ohne Seriennummern
  - gekoppelte Bluetooth-Geräte, nur wenn die App die Bluetooth-Berechtigung schon hat
  - die gespeicherten Diagnose-Mitschnitte (mit Hinweis auf Positionsdaten)
  - Absturzberichte von gpsloader
- Das Menü „Diagnose“ entfällt; „Letzten Mitschnitt sichern …“ geht im Support-Paket auf.

Betroffen sind alle Geräte des Katalogs (`docs/legacy-device-catalog.md`) im Direktmodus, unabhängig von der
Treiberfamilie. Neue Logger-Familien entstehen nicht.

## Capabilities

### New Capabilities

- `support-package`: Support-Paket als ZIP und das App-Protokoll, das darin landet.

### Modified Capabilities

- `diagnostic-capture`: Der Mitschnitt läuft immer; der Export einzelner Mitschnitte geht im Support-Paket auf.

## Nicht im Umfang

- Versand per Mail oder Upload; der Anwender verschickt das ZIP selbst (Entscheidung vom 2026-11-14).
- Mitschnitte von Dateikonvertierungen und die konvertierten Dateien selbst.
- Systemweite Protokolle (`log show`, sysdiagnose) und Protokolle anderer Prozesse.
- Die neue Fensteraufteilung (Change `main-window-sections`) und Anschluss-Hinweise (Change `device-ports-and-hints`).

## Impact

- GPSLoaderKit: neues Modul `SupportPackage` (Protokoll, Systembericht, Paket), `DiagnosticCapture` ohne Schalter,
  `BluetoothTransport` liefert die gekoppelten Geräte ohne Berechtigungsdialog.
- App: `DiagnosticsController` wird zum Support-Paket-Dialog, Menü „Hilfe“, Fehlermeldungen mit Knopf,
  Protokolleinträge in `SessionPresenter`, `DevicePanel`, `ConversionPresenter`, `AppDelegate`, Debug-Automation.
- Lokalisierung (de/en) der neuen Texte.
