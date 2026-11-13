# Proposal: gpsbabel, Qt und Rosetta aus der App entfernen

## Why

Alle Logger-Familien laufen inzwischen nativ über GPSLoggerKit und GPSLoggerKitGPL. Mit `magellan-port`, `itracku-port` und `alan-port` gilt das auch für die letzten Familien. Trotzdem liefert die App noch gpsbabel 1.7.0 als x86_64-Binary mit Qt 5.12 aus, prüft es beim Start und zeigt „Bereit – gpsbabel 1.7.0“ an. Der Entwickler hat am 2026-11-13 entschieden, gpsbabel ganz zu entfernen. Die übrigen Programmformate der myTracks-Formatliste entfallen damit; auch das hat er am selben Tag entschieden.

## What Changes

- **BREAKING – gpsbabel-Laufzeit entfällt:**
  - das Modul `GPSBabelRuntime` mit `ProcessRunner` und `ProcessRegistry` sowie seine Tests;
  - `Vendor/gpsbabel-1.7.0` (Binary, `QtCoreGpsBabel.framework`, PROVENANCE);
  - die Prüfung beim Start und das Beenden von Kindprozessen beim Quit.
- **BREAKING – Rosetta-Unterstützung entfällt:** das Ziel `RosettaInstaller`, `App/RosettaInstallation.swift` und die Fehlerart „Rosetta fehlt“.
- **Hauptfenster:** Der Bereich „Umgebung“ mit dem gpsbabel-Status entfällt.
- **Über-Fenster:** Die Hinweise auf gpsbabel 1.7.0 als mitgeliefertes Programm und auf Qt entfallen.
  - Erhalten bleiben die Lizenz der App, GPSLoggerKit (MIT) und die Urheber der portierten Vorlagen, darunter weiterhin GPSBabel.
- **Lizenztexte im Bundle:** nur noch GPL-3.0 (Lizenz der App) und MIT (GPSLoggerKit). GPL-2.0 und LGPL-3.0 entfallen, weil kein Programm unter diesen Lizenzen mehr mitgeliefert wird.
- **Build und Prüfung:**
  - `Scripts/sign-helpers.sh` und die Bauphase dafür entfallen.
  - `Scripts/verify-bundle.sh` prüft nun, dass es kein `Contents/Helpers` und kein `Contents/Frameworks/QtCoreGpsBabel.framework` gibt und dass die App arm64 und x86_64 enthält.
- **Fehlerarten:** `rosettaMissing` und `gpsbabelFailed` entfallen samt Texten.
- **Diagnose-Mitschnitt:** Prozess-Einträge (`ProcessRecord`) entfallen. Die Kopfangabe „unter Rosetta“ bleibt, denn Anwender können die App selbst unter Rosetta starten.
- **Demo-Treiber und Debug-Automation:** Der Fall „Kindprozess“ und die simulierten gpsbabel-Zustände entfallen.
- **Dokumentation:** `openspec/config.yaml`, `CLAUDE.md` und `README.md` beschreiben eine App ohne gpsbabel.
  - In `config.yaml` betrifft das: Vertrieb, Treiber-Architektur, die Abschnitte gpsbabel und Rosetta, „Weiterhin über gpsbabel“, den Umfang und den Diagnose-Mitschnitt.
  - `docs/legacy-*.md` beschreiben die Alt-App und bleiben unverändert.

## Entfallende Formate

Gestrichen werden 45 Einträge der Formatliste der Alt-App (`GPSBabel.m`, 68 Einträge). Es sind Formate von Karten-, Navigations- und PC-Programmen, keine Logger-Formate. Entscheidung des Entwicklers vom 2026-11-13:

`baroiq`, `cst`, `compegps`, `axim_gpb`, `gpl`, `saroute`, `destinator_trl`, `g7towin`, `glogbook`, `gdb`, `mapsource`, `garmin_txt`, `pcx`, `ggv_ovl`, `ggv_log`, `google`, `gnav_trl`, `gtm`, `hiketech`, `humminbird_ht`, `humminbird`, `ignrando`, `igo8`, `jtr`, `ktf2`, `kompass_tk`, `psitrex`, `lowranceusr`, `mapsend`, `ik3d`, `mapasia_tr7`, `tpo2`, `tpo3`, `navitel_trk`, `ozi`, `pathaway`, `sportsim`, `stmsdf`, `stmwpp`, `xol`, `dmtlog`, `unicsv`, `vidaone`, `vitosmt`, `vitovtt`.

Die übrigen 23 Einträge sind nativ umgesetzt oder fehlten schon in gpsbabel 1.7.0 (`cetus`, `coto`). Nativ umgesetzt sind 18 von ihnen, mit `magellan-port` und `alan-port` kommen drei dazu (`magellan`, `magellanx`, `alantrl`).

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Geräte:** Keines entfällt zusätzlich. Alle Einträge, die bisher noch gpsbabel vorsahen, sind nativ umgesetzt, nämlich die Treiber `magellan`, `itracku` und `alantrl` durch die vorausgehenden Changes.
- **Folge für die Treiberfamilien:** Es gibt keine gpsbabel-Treiber mehr, nur noch native Treiber.

## Berührte Vorschläge aus der Exploration

- **„Holux GPSport 245 – alternative als festen Ablauf mit zwei gpsbabel-Aufrufen übernehmen“:** Dieser Vorschlag wird gegenstandslos. Der GPSport 245 läuft über den nativen Holux-Treiber (`mtk-device-port`). Das folgt aus der Entscheidung, gpsbabel zu entfernen. Der Entwickler bestätigt es mit der Freigabe dieses Changes, danach wird der Punkt aus `config.yaml` gestrichen.
- **Wintec WPL 1000 / Navilock NL-456DL:** Dieser Vorschlag ist nicht berührt.

## Reihenfolge

Umgesetzt wird erst nach `magellan-port`, `itracku-port` und `alan-port`. Archiviert wird nach `gpl-driver-package`, weil beide die Anforderung „Lizenzhinweise“ in `app-shell` ändern.

## Capabilities

### New Capabilities

(keine)

### Modified Capabilities

- `gpsbabel-runtime`: Alle Anforderungen entfallen, die Capability wird stillgelegt.
- `app-shell`: „Umgebungsstatus im Hauptfenster“ entfällt. „Lizenzhinweise“ nennt gpsbabel und Qt nicht mehr als mitgelieferte Programme.
- `logger-session`: „Abbruch“ und „Einheitliche Fehlermeldungen“ werden durch Fassungen ohne gpsbabel ersetzt („Abbruch eines Vorgangs“, „Fehlermeldungen der Sitzung“). Es entfallen die Fehlerarten „Rosetta fehlt“ und „gpsbabel-Fehler“ und das Abbruch-Szenario für gpsbabel.
- `diagnostic-capture`: „Inhalt der Aufzeichnung“ wird durch „Inhalt des Mitschnitts“ ohne gpsbabel-Aufrufe ersetzt.

## Nicht im Umfang

- **Neue Formate** als Ersatz für die entfallenden 45 Programmformate. Wer sie braucht, kann gpsbabel selbst nutzen.
- **Inhalt der portierten Formate und Treiber:** Er bleibt unverändert, auch die Nennung von GPSBabel als Vorlage in `credits` und `PROVENANCE.md`.
- **Alt-App-Dokumentation** (`docs/legacy-analysis.md`, `docs/legacy-device-catalog.md`).
- **iOS.**

## Impact

- **App:**
  - Es entfallen `AppEnvironment` (Laufzeitstatus), `MainWindowController` (Bereich „Umgebung“), `RosettaInstallation.swift` und der Kindprozess-Fall in `DemoDriver`.
  - Angepasst werden `AboutWindowController`, `AppDelegate`, `DebugAutomation` und `Localizable.xcstrings`.
- **GPSLoaderKit:**
  - Es entfallen das Modul `GPSBabelRuntime` mit seinen Tests.
  - In `LoggerCore` (`LoggerError`, `Diagnostics`, Lokalisierung) und `DiagnosticCapture` (`CaptureRecorder`) entfallen die Teile für gpsbabel.
  - Angepasst wird `FileConversionTests/AppFormatsTests` (Ort des GPL-3.0-Texts).
- **Projekt:**
  - In `project.yml` entfallen Helpers, Qt, RosettaInstaller, die Signier-Phase und `GPSBabelRuntime`.
  - Es entfallen `Vendor/gpsbabel-1.7.0`, `RosettaInstaller/` und `Scripts/sign-helpers.sh`.
  - Angepasst wird `Scripts/verify-bundle.sh`.
- **Dokumentation:** `openspec/config.yaml`, `CLAUDE.md` und `README.md`.
