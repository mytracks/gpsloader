# myTracks Loader (Repository `gpsloader`)

Eigenständige macOS-App zum Auslesen von GPS-Loggern und zum Konvertieren von Logger-Dateien nach GPX.
Sie ersetzt die Logger-Funktionen der App myTracks. Vertrieb per Download, nicht über den App Store.
Für Anwender heißt die App „myTracks Loader“ (seit 2026-11-19, Change `rename-and-icon`); Repository, Target,
Module und Bundle-ID heißen weiter `gpsloader`. Das Icon erzeugt `Scripts/make-app-icon.swift` (`App/AppIcon.icon`).

## Arbeitsweise

- Die Entwicklung läuft spec-getrieben mit **OpenSpec** (`openspec/`). Vor neuen Features einen
  Change anlegen (`/opsx:propose`) und nicht direkt implementieren.
- Verbindlich sind Projektkontext, Entscheidungen und Artefakt-Regeln in `openspec/config.yaml`.
  Punkte, die dort als „noch nicht bestätigt“ markiert sind, vor der Umsetzung mit dem Entwickler klären.
- Kommunikation und OpenSpec-Artefakte auf Deutsch. Code, Bezeichner und Kommentare auf Englisch.

## Wichtige Orte

- `docs/legacy-analysis.md`: fachliche Analyse der Alt-Implementierung. Enthält Treiber, Protokolle
  (BG728, GNS2000, i-GotU, NAL), gpsbabel-Versionen und Abläufe.
- `docs/legacy-device-catalog.md`: alle Geräte des aktuellen myTracks-Stands mit Treiberzuordnung.
  Nicht enthalten sind i-GotU und WPL 1000, siehe Analyse.
- `docs/hardware-tests.md`: offene Hardware- und Anwendertests der archivierten Changes, mit Prüfkriterien.
- `input/mytracks4mac/`: Originalcode von myTracks als Git-Repository. **Nur lesen**, nicht ändern,
  nicht in den Build übernehmen. Der Ordner ist per `.gitignore` nicht versioniert. Die relevanten Stellen:
  - `DsTrackFramework/Source/Classes/GpsDriver/`: interne Treiber BG728 und GNS2000.
  - `DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`: Treiberauswahl und gpsbabel-Aufrufe.
  - `myTracks/Source/Resources/gpslogger.plist`: Gerätekatalog.
  - `myTracks/Source/Resources/wsg2000/wsg2000.c`: Beschreibung des NAL-Formats.
  - `myTracks/Source/Classes/Controller/MyTracksMainController.m`: Import- und Lösch-Ablauf (ca. Zeile 1800–2200).
  - `myTracks/Source/Classes/Controller/GpsLoggerWizard.m`: Einrichtungsassistent und Geräteerkennung.
  - Gelöschter Code in der Historie:
    - i-GotU-Treiber unter `git show 3cbc727^:DsTrackFramework/Source/Classes/GpsDriver/IGotUGT800.m` (bzw. `IGotU.m`).
    - gpsbabel 1.7.0 im Commit `e0d1f18`.
  - `Import/Apps/GPSBabelFE170.app` und `Import/install-gpsbabel170.sh`: Quelle des gpsbabel-1.7.0-Binaries samt Qt 5
    (nur für Black-Box-Gegenprüfungen).

## Technische Leitplanken (Kurzfassung)

- Minimum macOS 12. Die App ist ein Universal Binary ohne Hilfsprogramme; sie braucht kein Rosetta.
- Nur Swift (Swift 6 Language Mode, Strict Concurrency). Kein ObjC/C/C++ im Projekt.
- Kein gpsbabel in der App (entschieden am 2026-11-13, Change `remove-gpsbabel`); alle Treiber sind nativ.
  Das gpsbabel-1.7.0-Binary der Alt-App (Commit `e0d1f18`) dient nur der Black-Box-Gegenprüfung: in den
  Scratchpad kopieren, nie ins Repository; Aufruf als Prozess mit Argument-Array, nie über eine Shell.
- Noch offene native Treiber: BG728 (Paket noch nicht entschieden) und WSG-2000 NAL (GPSLoggerKit, Black-Box). GNS2000 läuft über IOBluetooth/RFCOMM (Change `gns2000-driver`).
- Bluetooth-Logger nur über `/dev/cu.*`.
- Keine Python- oder Perl-Abhängigkeit, kein `system()`/`popen()`.
- Protokoll- und Parser-Logik in UI-unabhängigen Swift-Packages, ohne Hardware testbar.
- **Pakete in eigenen Repositories** (seit 2026-11-19, Change `split-repositories`), eingebunden in
  `Packages/GPSLoaderKit/Package.swift` per URL und `.upToNextMinor`, Stände in `Packages/GPSLoaderKit/Package.resolved`:
  - [GPSLoggerKit](https://github.com/mytracks/GPSLoggerKit) (**MIT**, macOS 12+ und iOS/iPadOS 27+, Clean-Room;
    auch von myTracks Neo genutzt). Lokal: `/Volumes/Dev/Projects/GPSLoggerKit`.
  - [GPSLoggerKitGPL](https://github.com/mytracks/GPSLoggerKitGPL) (**GPL-3.0-or-later**, nur macOS, Portierungen).
    Lokal: `/Volumes/Dev/Projects/GPSLoggerKitGPL`.
  - Formate und Geräteprotokolle ändern sich nur mit einem Change im jeweiligen Paket-Repository, dort gelten dessen
    `CLAUDE.md` und `openspec/config.yaml` (Clean-Room bzw. Regeln für Portierungen). **In diesem Repository wird kein
    GPL-Quelltext gelesen.**
  - Ein Change arbeitet in genau einem Repository: erst Paket-Change mit Release, dann ein Change hier, der die Version
    anhebt und Katalog, Transport oder UI ergänzt. Zum Entwickeln gegen lokale Paketstände siehe README, „Pakete“.
- Lizenz der App: GPL-3.0-or-later (`LICENSE`). Release-Builds brauchen die Adresse des Quellcodes
  (`GPSLOADER_SOURCE_CODE_URL` in `project.yml`).
- Der Entwickler hat keine i-GotU- und Bluetooth-Logger; diese testen die Anwender.
  Der Agent hat keine Hardware.
