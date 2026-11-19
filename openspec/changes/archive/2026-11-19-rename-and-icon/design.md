# Design: App in „myTracks Loader“ umbenennen und ein Icon geben

## Context

- **Name heute:** In `project.yml` sind `PRODUCT_NAME` und `INFOPLIST_KEY_CFBundleDisplayName` `gpsloader`. Das Bundle heißt `gpsloader.app`.
  - Menüs und Fenstertitel lesen `CFBundleDisplayName` (`MainMenuBuilder`, `MainWindowController`).
  - Das Über-Fenster hat den Namen fest im Code (`AboutWindowController`).
- **Name in Texten:** Sieben Schlüssel in `App/Localizable.xcstrings` und vier Einträge in `App/InfoPlist.xcstrings` enthalten „gpsloader“. Dazu kommen feste Texte in GPSLoaderKit:
  - Kopf und README des Support-Pakets (`SupportPackageBuilder`, `SystemReport`);
  - die Fehlertexte in `RFCOMMTransport` und `CaptureFormat`.
- **Ablageorte:**
  - `~/Library/Logs/gpsloader/gpsloader.log` (`AppLog`);
  - `~/Library/Application Support/gpsloader/` (`CaptureStore`);
  - die Absturzberichte werden über das Präfix „gpsloader“ gesucht (`CrashReports.find`).
- **GPX:** `creator` ist `"gpsloader \(appVersion)"` (`AppEnvironment.gpxCreator`).
- **Icon:** Die App hat keines (`ASSETCATALOG_COMPILER_APPICON_NAME: ""`).
- **Vorlage myTracks Neo:** `Apps/myTracksNeo/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` ist ein randloses Quadrat mit senkrechtem Verlauf. Abgelesen: oben `#1A46DE`, Mitte `#5C30BC`, unten `#9F199C`. Darauf liegt eine weiße Weltkugel in Linien von etwa 26 px Stärke bei 1024 px.
- **Rechner:** Der Entwicklungsrechner läuft unter macOS 27 mit Xcode 27.1. Das Minimum der App ist macOS 12.

## Goals / Non-Goals

**Goals:**
- Anwender sehen nur „myTracks Loader“; gespeicherte Einstellungen bleiben erhalten.
- Das Icon passt zu myTracks Neo, wirkt auf macOS 12–15 wie auf macOS 26+ richtig und ist reproduzierbar.
- Bestehende Protokolle und Mitschnitte gehen beim Umbenennen nicht verloren.

**Non-Goals:**
- Interne Kennungen umbenennen: Target, Module, Bundle-ID, Queue-Namen, Mitschnittkennung.
- Dokument-Icons.

## Decisions

### D1 Name im Projekt, nicht im Code

- **`project.yml`:** `PRODUCT_NAME: "myTracks Loader"` und `INFOPLIST_KEY_CFBundleDisplayName: "myTracks Loader"`. Bundle und Programmdatei heißen dann `myTracks Loader`.
- **Code:** `AboutWindowController` liest den Namen wie die anderen Stellen aus `CFBundleDisplayName`. Der Rückfallwert im Code ist „myTracks Loader“.
- **Lokalisierte Texte:** Sie nutzen den Namen als festen Text. „myTracks Loader“ wird nicht übersetzt, Platzhalter machen die Übersetzung schwerer als nötig.
- **Schlüssel:** In `Localizable.xcstrings` entstehen neue Schlüssel mit dem neuen Namen, die alten entfallen. `Scripts/check-localizations.swift` meldet danach weder fehlende noch veraltete Schlüssel.
- **Bundle-ID:** Sie bleibt `info.stichling.gpsloader`, damit Einstellungen (`UserDefaults`-Domäne) und Bluetooth-Berechtigung (TCC) erhalten bleiben. Eine neue Bundle-ID würde beides verwerfen.

### D2 Ablageorte und Übernahme

| Inhalt | Neu | Alt |
|---|---|---|
| Protokoll | `~/Library/Logs/myTracks Loader/myTracks Loader.log` (rotiert `myTracks Loader.N.log`) | `~/Library/Logs/gpsloader/` |
| Mitschnitte | `~/Library/Application Support/myTracks Loader/` | `~/Library/Application Support/gpsloader/` |
| Support-Paket | `myTracks-Loader-Support-yyyyMMdd-HHmm.zip` | `gpsloader-support-…` |

- **Ordnernamen:** Sie kommen aus einer Konstante im Modul `SupportPackage` bzw. `DiagnosticCapture`, nicht aus dem Bundle. So bleiben die Pakete ohne Bundle testbar.
- **Übernahme:** Beim Start verschiebt die App einen alten Ordner per `FileManager.moveItem`, wenn der neue noch fehlt. Das geschieht, bevor `AppLog` und `CaptureStore` zum ersten Mal schreiben (synchron in `applicationWillFinishLaunching`).
  - Scheitert das Verschieben, schreibt die App in den neuen Ordner. Den Fehler protokolliert sie, der alte Ordner bleibt.
  - Gibt es beide Ordner, wird nichts verschoben.
  - **Alte Protokolldateien:** Nach dem Verschieben benennt `AppLog.adoptLegacyFiles()` `gpsloader.log` und `gpsloader.N.log` in die neuen Namen um, als die ältesten Dateien. So erfassen Rotation und Support-Paket sie. Dateien über der Höchstzahl entfallen wie bei der Rotation.
- **Absturzberichte:** Sie werden über die Präfixe „myTracks Loader“ und „gpsloader“ gesucht.
- **Mitschnittkennung:** Die Kennung im Mitschnittformat bleibt `gpsloader-capture`. Sichtbar ist nur der Fehlertext, und der nennt künftig „myTracks Loader“.

### D3 GPX-Creator

`AppEnvironment.gpxCreator` liefert „myTracks Loader <Version>“. Den Test für das Attribut (Szenario „Creator“) gibt es in GPXExport mit festem Namen und fester Version.

### D4 Icon: Quelle und Erzeugung

- **Skript:** `Scripts/make-app-icon.swift` (Swift, CoreGraphics, kein Drittwerkzeug) erzeugt das Icon aus einer festen Geometrie:
  - **Hintergrund:** linearer Verlauf von oben `#1A46DE` nach unten `#9F199C`, wie bei myTracks Neo.
  - **Satellit:** weiße Linien, Strichstärke 26 px bei 1024 px, runde Enden. Er besteht aus einem um etwa 45° gedrehten Körper und zwei Solarflügeln mit Gitter an Streben. Dazu kommen eine Antenne und zwei bis drei Funkwellen als Kreisbögen.
  - **Verlauf:** Der Verlauf läuft durch und ist nicht gestuft.
- **Ausgaben:**
  1. **`App/AppIcon.icon` (Icon Composer, macOS 26+):** Der Verlauf ist die Hintergrundfüllung, der Satellit eine SVG-Ebene, ohne eigene Maske. Das System legt Form, Glas und Schatten darüber.
  2. **`App/Assets.xcassets/AppIcon.appiconset` (macOS 12–15):** Größen 16 bis 512 pt in @1x und @2x. Gezeichnet nach dem macOS-Raster: abgerundetes Quadrat von 824 × 824 px im 1024er-Feld mit leichtem Schatten.
- **Auswahl:** Das Skript kann mit `--variant <n>` mehrere Satelliten-Varianten als Vorschau erzeugen. Der Entwickler wählt eine, und nur diese wird eingebaut.
- **Gewählt (Entwickler, 2026-11-19):** Variante 3, also der Satellit waagerecht mit drei Funkwellen darüber, ohne Korrekturen.
- **Reproduzierbar:** Die erzeugten Dateien liegen im Repository. Ein erneuter Lauf ergibt dieselben Bytes; das Skript schreibt PNGs ohne Zeitstempel.
- **`project.yml`:** `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
  - **Xcode 26 und neuer:** Ob Xcode aus `AppIcon.icon` selbst die Bilder für macOS 12–15 erzeugt, wird bei der Umsetzung geprüft. Wenn ja, entfällt das `appiconset`. Ein Icon im Projekt bleibt die Quelle.

Alternative „nur `appiconset`“: verworfen. Ab macOS 26 setzt das System Icons ohne passende Form verkleinert in eine graue Fläche. Das widerspricht dem Ziel, wie myTracks Neo zu wirken.

### D5 Über-Fenster

Das Über-Fenster zeigt das App-Icon (`NSApp.applicationIconImage`) über dem Namen. Für das Szenario „Über-Fenster“ gibt es einen Snapshot.

### D6 Skripte

- **`release.sh`:** Das Bundle ist `export/myTracks Loader.app`, das ZIP `myTracks-Loader-<Version>.zip`. Alle Pfade sind in Anführungszeichen, wegen des Leerzeichens.
- **`verify-bundle.sh`:** Es leitet die Programmdatei schon heute aus dem Bundle-Namen ab und wird auf Leerzeichen geprüft.
- **README:** Die Debug-Beispiele verweisen auf `myTracks Loader.app/Contents/MacOS/myTracks Loader`.

### Concurrency

- **Übernahme der Ordner (D2):** Sie läuft synchron auf dem Main Actor, bevor die Dienste starten. `AppLog` ist `Sendable` und bekommt den fertigen Ordner im Initialisierer. Es gibt keine nebenläufigen Zugriffe auf den alten Ordner.
- **Icon-Skript:** Es läuft außerhalb der App und hat keine Isolation.

## Risks / Trade-offs

- **Leerzeichen im Bundle-Namen:** Skripte und Debug-Aufrufe brechen ohne Anführungszeichen. → Alle Skripte setzen Pfade in Anführungszeichen. `release.sh --skip-notarize` und `verify-bundle.sh` laufen nach der Umstellung grün.
- **Name in TCC:** Der Systemdialog zur Bluetooth-Berechtigung zeigt den neuen Namen. Bestehende Berechtigungen hängen an der Bundle-ID und bleiben.
- **Absturzberichte:** Ältere Berichte heißen „gpsloader-…“. → Sie werden über beide Präfixe gefunden (D2).
- **Wirkung des Icons:** Ob es auf macOS 12–15 und auf macOS 26+ wie gewünscht aussieht, lässt sich nur am echten System beurteilen. → Dafür gibt es eine manuelle Prüfung durch den Entwickler (Task).
- **GitHub-Dateiname:** Leerzeichen werden zu Punkten. → Das ZIP nutzt Bindestriche.

## Open Questions

- **Geklärt am 2026-11-19 (D4):** Xcode 27.1 rendert aus `AppIcon.icon` selbst alle Größen von 16 bis 1024 px für macOS 12–15 in `Assets.car` und dazu ein `AppIcon.icns`. Mit `actool` geprüft: Ein zusätzliches `appiconset` gleichen Namens wird ignoriert. Es entfällt deshalb; das Skript schreibt nur `App/AppIcon.icon`, die Vorschau in macOS-Form bleibt für die Auswahl.
- **Beobachtung:** Wird die Programmdatei direkt gestartet (Debug-Automation), liefert `NSApp.applicationIconImage` das allgemeine Symbol. Bei einem Start über Launch Services (`open`, Finder, Dock) erscheint das Icon. Snapshots des Über-Fensters entstehen deshalb mit `open -n … --args`.
