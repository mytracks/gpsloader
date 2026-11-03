# gpsloader

Eigenständige macOS-App zum Auslesen von GPS-Loggern und zum Konvertieren von Logger-Dateien nach GPX.
Sie ersetzt die Logger-Funktionen der App myTracks. Vertrieb per Download, nicht über den App Store.

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
  - `Import/Apps/GPSBabelFE170.app` und `Import/install-gpsbabel170.sh`: Quelle des gpsbabel-1.7.0-Binaries samt Qt 5.

## Technische Leitplanken (Kurzfassung)

- Minimum macOS 12. Die App ist ein Universal Binary.
- Nur Swift (Swift 6 Language Mode, Strict Concurrency). Kein ObjC/C/C++ im Projekt.
- gpsbabel ausschließlich in Version 1.7.0, als fertiges x86_64-Binary. Nicht selbst bauen.
  Aufruf als Prozess mit Argument-Array, nie über eine Shell. Auf Apple Silicon ist Rosetta nötig;
  die App muss fehlendes Rosetta erkennen.
- Native Swift-Treiber: BG728, GNS2000, i-GotU (GT-800 seriell, übrige Modelle über USB/HID) und WSG-2000 NAL.
- Bluetooth-Logger nur über `/dev/cu.*`.
- Keine Python- oder Perl-Abhängigkeit, kein `system()`/`popen()`.
- Protokoll- und Parser-Logik in UI-unabhängigen Swift-Packages, ohne Hardware testbar.
- `Packages/GPSLoggerKit`: eigenständiges Paket (macOS 12+, iOS/iPadOS 27+, **MIT-Lizenz**), wird später
  in ein eigenes Repository ausgelagert. Keine Abhängigkeit auf andere Teile dieses Repositorys.
  **Clean-Room:** GPL-Quelltext (gpsbabel, igotu2gpx, wsg2000.c u. a.) weder lesen noch übersetzen;
  nur öffentliche Spezifikationen, eigener myTracks-Code und Black-Box-Beobachtung. Details in `openspec/config.yaml`.
- Der Entwickler hat keine i-GotU- und Bluetooth-Logger; diese testen die Anwender.
  Der Agent hat keine Hardware.
