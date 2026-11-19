# Design: support-package

## Context

- `DiagnosticCapture` (GPSLoaderKit): `CaptureRecorder` zeichnet einen Vorgang im Speicher auf, `CaptureStore`
  speichert ihn unter `~/Library/Application Support/gpsloader/Captures` (höchstens 10) und hält den Schalter
  `DiagnosticCaptureEnabled`. `SessionPresenter.makeSession` erzeugt einen Recorder nur bei eingeschaltetem
  Schalter, `finish` speichert ihn nach jedem Ausgang (auch bei Fehlern).
- `DiagnosticsController` und das Menü „Diagnose“ bieten Schalter und „Letzten Mitschnitt sichern …“.
- Die App ist nicht sandboxed (`openspec/config.yaml`), darf also `~/Library/Logs` lesen und schreiben.
- Es gibt kein App-Protokoll. In myTracks schrieb `MyLog` (`input/mytracks4mac/DsUtilities/Source/Classes/Utilities/MyTrace.m`)
  nur nach NSLog, also ins Systemprotokoll, aus dem Anwender es kaum herausholen konnten.

## Goals / Non-Goals

**Goals:**
- Paket ohne Fremdcode, ohne Shell und ohne zusätzliche Berechtigungsdialoge.
- Alle Sammelfunktionen ohne UI testbar, mit austauschbaren Quellen.

**Non-Goals:**
- Kein eigenes ZIP-Format oder Kompressionscode.
- Keine Anzeige des Protokolls in der App.

## Decisions

### D1 Neues Modul `SupportPackage` in GPSLoaderKit

Enthält `AppLog`, `SystemReport` und `SupportPackageBuilder`; hängt von `LoggerCore`,
`SerialTransport` und `DiagnosticCapture` ab. Die Bluetooth-Liste liefert `BluetoothTransport`
(`PairedBluetoothDevices.listIfAuthorized()`), weil nur dieses Modul IOBluetooth importiert; die App reicht
das Ergebnis als Text an den Builder. Alternative: alles in der App – verworfen, weil dann nichts ohne UI testbar ist.

### D2 App-Protokoll als eigene Datei

`AppLog` ist eine `final class: Sendable` mit einem `Locked`-Zustand und schreibt jede Zeile synchron
(`ISO-8601-Zeit Kategorie Text`) nach `~/Library/Logs/gpsloader/gpsloader.log`, zusätzlich an `os.Logger`
(Subsystem `info.stichling.gpsloader`) für Console.app. Überschreitet die Datei 1 MB, wird sie zu
`gpsloader.1.log` usw. verschoben; es bleiben höchstens 5 Dateien (zusammen ≤ 5 MB). Verzeichnis und
Grenzen sind für Tests einstellbar. `AppLog.shared` ist ein `static let` (Sendable).
Alternative `OSLogStore`: liest unter macOS 12 nur den laufenden Prozess, frühere Starts gingen verloren.

Was protokolliert wird, legt die App fest (Start, Ports, Auswahl, Vorgänge, Konvertierungen, Fehler). Für
Konvertierungen nur Anzahl und Format-IDs, keine Dateinamen; für Vorgänge Treiber-ID, Anschluss und Ergebnis.

### D3 Systembericht und Geräteliste

- `SystemReport.current(appVersion:build:)`: `ProcessInfo` (macOS-Version), `sysctlbyname("hw.model")`,
  Architektur und Rosetta wie `CaptureEnvironment`, `Locale.preferredLanguages`, `TimeZone.current.identifier`.
- `USBDeviceCatalog.currentDevices()` in `SerialTransport` (IOKit, Klasse `IOUSBHostDevice`): je Gerät `idVendor`,
  `idProduct`, `USB Product Name`, `USB Vendor Name`, `locationID`. Seriennummern werden nicht gelesen. Der
  Change `device-ports-and-hints` nutzt dieselbe Liste, um fehlende Treiber zu erkennen.
- Serielle Anschlüsse aus `SerialPortCatalog.currentPorts()`.
- Einstellungen: `UserDefaults.standard.persistentDomain(forName:)` als XML-Property-List.
- Absturzberichte: Dateien `gpsloader*` in `~/Library/Logs/DiagnosticReports` (auch `Retired`).

Alle Teile werden als Text (bzw. Kopie der Datei) geschrieben; der Builder bekommt sie über ein
`SupportPackageSources`-Wertobjekt mit Closures, damit Tests feste Inhalte einsetzen können.

### D4 ZIP über `NSFileCoordinator`

Der Builder schreibt die gewählten Teile in einen temporären Ordner `gpsloader-support-…/` und ruft
`NSFileCoordinator().coordinate(readingItemAt:options: .forUploading)` auf. Foundation legt dabei ein ZIP des
Ordners an, das im Block an den Zielort kopiert wird; danach wird der temporäre Ordner gelöscht.
Alternativen: eigener ZIP-Schreiber (unnötiger Code) oder `/usr/bin/ditto` als Prozess (vermeidbar).

Ablauf im ZIP:

```
gpsloader-support-20261114-1030/
  README.txt            Übersicht: Erstellzeit, App-Version, enthaltene Teile
  system.txt
  log/gpsloader*.log
  settings.plist
  ports-and-usb.txt
  bluetooth.txt         nur wenn gewählt und verfügbar
  captures/*.jsonl
  crash-reports/*.ips
```

### D5 Concurrency

`SupportPackageBuilder.build(...)` ist `async` und `nonisolated`; die App ruft es aus einem `Task` auf, sodass
Kopieren und Zippen nicht den Main Thread blockieren. Die Bluetooth-Liste wird vorher auf dem MainActor
geholt (IOBluetooth). Ein Abbruch ist nicht vorgesehen (Sekundenbruchteile); Fehler beim Schreiben werden
als `LoggerError(.writeFailed)` gemeldet.

### D6 Mitschnitt immer aktiv

`CaptureStore.isEnabled` und `enabledKey` entfallen; `AppEnvironment.makeRecorder()` liefert immer einen
Recorder. Die alte Einstellung bleibt unbeachtet in den Defaults liegen.

### D7 UI

- `SupportPackageController` (App, ersetzt `DiagnosticsController`): Sheet mit Häkchen je Teil, Anzahl der
  Mitschnitte und Absturzberichte, Hinweis auf Positionsdaten, Bluetooth deaktiviert mit Hinweis, wenn keine
  Berechtigung besteht; danach `NSSavePanel`.
- Menü „Hilfe“ (`NSApp.helpMenu`) mit „Support-Paket erstellen …“; das Menü „Diagnose“ entfällt.
- `SessionPresenter.showError` bekommt den Knopf „Support-Paket erstellen …“ für fehlgeschlagene Vorgänge.
- Debug-Automation: `-DebugShowCaptureExport` wird zu `-DebugShowSupportPackage <s>`, dazu
  `-DebugSupportPackagePath <datei>` zum Schreiben ohne Dialoge.

## Risks / Trade-offs

- [Zweite Kopie der Positionen in Application Support] → begrenzt auf 10 Vorgänge, nur lokal, Hinweis in der Inhaltsliste.
- [`.forUploading` ist als Verhalten dokumentiert, aber nicht als ZIP-API] → Test prüft, dass ein gültiges ZIP mit den erwarteten Einträgen entsteht.
- [Absturzberichte enthalten Pfade mit dem Benutzernamen] → als Teil abwählbar; in der Übersicht erwähnt.
- [Zeitzone und Sprache sind persönliche Angaben] → nötig für Zeitprobleme (Ortszeit-Formate); im Systembericht sichtbar.
