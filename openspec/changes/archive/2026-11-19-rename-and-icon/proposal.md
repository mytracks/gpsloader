# Proposal: App in „myTracks Loader“ umbenennen und ein Icon geben

## Why

Für das erste öffentliche Release soll die App für Anwender „myTracks Loader“ heißen (Entscheidung des Entwicklers vom 2026-11-19). Der Name ordnet sie myTracks zu, dessen Logger-Funktionen sie ablöst. Das Repository heißt weiter `gpsloader`.

Bisher hat die App kein Icon. Sie soll eines im Stil von myTracks Neo bekommen:
- **Hintergrund:** derselbe wie bei myTracks Neo, ein senkrechter Verlauf von Blau nach Violett.
- **Motiv:** ein weißer Satellit an Stelle der Weltkugel.

## What Changes

- **Name für Anwender:** „myTracks Loader“ erscheint überall, wo Anwender den Namen sehen:
  - Programmname im Finder und im Dock, Menü „myTracks Loader“ und dessen Befehle („Über …“, „… beenden“);
  - Fenstertitel und Über-Fenster;
  - Texte der Lokalisierung, zum Beispiel der Bluetooth-Hinweis und der Hinweis zum Koppeln;
  - die Begründung des Bluetooth-Zugriffs im Systemdialog.
- **Dateinamen und Ablageorte:**
  - **App-Bundle:** `myTracks Loader.app`.
  - **ZIP des Releases:** `myTracks-Loader-<Version>.zip`. Bindestriche, weil GitHub Leerzeichen in Dateinamen durch Punkte ersetzt.
  - **Support-Paket:** `myTracks-Loader-Support-<Datum>-<Uhrzeit>.zip`.
  - **App-Protokoll:** in `~/Library/Logs/myTracks Loader/`.
  - **Diagnose-Mitschnitte:** im Ordner „myTracks Loader“ in Application Support.
  - **Übernahme:** Ordner mit dem alten Namen „gpsloader“ übernimmt die App beim ersten Start.
- **GPX-Dateien:** Das Attribut `creator` lautet „myTracks Loader <Version>“.
- **Icon:**
  - **Hintergrund:** senkrechter Verlauf von `#1A46DE` (oben) nach `#9F199C` (unten), abgelesen aus dem Icon von myTracks Neo.
  - **Motiv:** ein weißer Satellit in Linienzeichnung mit Körper, zwei Solarflügeln und Funkwellen, in der Strichstärke der Weltkugel von myTracks Neo.
  - **Erzeugung:** Ein Swift-Skript erzeugt das Icon reproduzierbar.
  - **Auswahl:** Der Entwickler wählt aus Varianten, bevor es eingebaut wird.
- **Unverändert:**
  - Repository-Name, Xcode-Target `gpsloader` und Bundle-ID `info.stichling.gpsloader`. Die Bundle-ID sehen Anwender nicht; eine neue würde gespeicherte Einstellungen verwerfen.
  - Die Kennung des Mitschnittformats (`gpsloader-capture`), damit vorhandene Mitschnitte und Test-Fixtures lesbar bleiben.
- **Dokumentation:** README, `CLAUDE.md` und `openspec/config.yaml` nennen den Namen. In `config.yaml` entfällt „gpsloader (Arbeitstitel)“.
- **Skripte:** `Scripts/release.sh` und `Scripts/verify-bundle.sh` arbeiten mit dem neuen Bundle- und ZIP-Namen.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

Keine. Gerätekatalog und Treiberfamilien bleiben unverändert.

## Berührte Vorschläge aus der Exploration

- **„Rückweg zu myTracks: erzeugte GPX-Datei per ‚In myTracks öffnen‘ übergeben“:** nicht berührt. Der Name legt diese Funktion nicht fest.

## Nicht im Umfang

- Umbenennen des Repositorys, des Xcode-Targets, der Bundle-ID und der Swift-Module.
- GitHub-Releases (Change `split-repositories`).
- Ein Icon für Dokumente oder Mitschnittdateien.
- Eine Website oder Produktseite.

## Reihenfolge

`support-package` wird vor diesem Change archiviert, weil dieser Change dessen Anforderungen zu Dateinamen und Protokoll-Ordner ändert. `main-window-sections` und `device-ports-and-hints` berühren keine Anforderung dieses Changes. Vor `split-repositories` umsetzen.

## Capabilities

### New Capabilities

(keine)

### Modified Capabilities

- `app-shell`: neue Anforderungen „Name der App“ und „App-Icon“. „Lizenzhinweise“ nennt das Über-Fenster mit dem neuen Namen.
- `gpx-export`: „GPX-1.1-Konformität“ verlangt „myTracks Loader“ im Attribut `creator`.
- `support-package`: In „Support-Paket erstellen“ ändert sich der Dateiname, in „Inhalt des Support-Pakets“ der Name der Absturzberichte, in „App-Protokoll“ der Ordner und die Übernahme des alten Ordners.

## Impact

- **App:**
  - **Fenster und Menüs:** `AboutWindowController`, `MainMenuBuilder`, `MainWindowController`, `DevicePanel`, `SupportPackageController`.
  - **Umgebung:** `AppEnvironment` (`creator`).
  - **Lokalisierung:** `App/Localizable.xcstrings`, `App/InfoPlist.xcstrings`.
  - **Neu:** `App/AppIcon.icon` mit dem App-Icon (Icon Composer).
- **GPSLoaderKit:**
  - **Ablageorte:** `SupportPackage` (`AppLog`, `SupportPackageBuilder`, `SystemReport` mit Absturzberichten und Kopfzeile) und `DiagnosticCapture` (`CaptureStore`) samt Übernahme des alten Ordners.
  - **Texte:** die Fehlertexte in `BluetoothTransport` und `DiagnosticCapture`.
- **Projekt:** In `project.yml` ändern sich `PRODUCT_NAME`, der Anzeigename und `ASSETCATALOG_COMPILER_APPICON_NAME`.
- **Skripte:** `Scripts/release.sh`, `Scripts/verify-bundle.sh`, neu `Scripts/make-app-icon.swift`.
- **Tests:** die Tests für Dateinamen, Protokoll und `creator`.
