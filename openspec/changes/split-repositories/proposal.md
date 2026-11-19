# Proposal: Pakete in eigene Repositories auslagern und Releases auf GitHub veröffentlichen

## Why

GPSLoggerKit soll auch in myTracks Neo laufen. Der Swift Package Manager lädt ein Paket aber nur aus einem Repository, das die `Package.swift` im Wurzelverzeichnis hat und seine Versionen als Git-Tags führt. Heute liegen beide Pakete als Unterordner im gpsloader-Repository.

Außerdem gibt es noch keine Veröffentlichung für Anwender:
- keine Releases auf GitHub;
- keine Versionen, auf die sich andere Projekte beziehen können.

Entscheidungen des Entwicklers vom 2026-11-19:
- **Repositories:** Die Pakete kommen in mehrere Repositories.
- **Lizenz von myTracks Neo:** myTracks Neo ist eine App-Store-App ohne offenen Quellcode. Sie darf deshalb nur das MIT-Paket nutzen.
- **Lizenz der App:** Die App bleibt unter der GPL.
- **Versionen:** Alle Versionen starten mit 0.1.0, weil noch wenig erprobt ist.
- **Sichtbarkeit:** Das Repository `mytracks/gpsloader` ist seit diesem Tag öffentlich.

## What Changes

- **Neues Repository `mytracks/GPSLoggerKit` (MIT, öffentlich):**
  - Inhalt ist der heutige Ordner `Packages/GPSLoggerKit` mit seiner Git-Historie (`git subtree split`), die `Package.swift` liegt im Wurzelverzeichnis.
  - Die Historie bleibt erhalten, weil sie den Clean-Room-Ablauf belegt, auf den sich `PROVENANCE.md` stützt.
  - Das Repository bekommt ein eigenes `openspec/` mit den Specs des Pakets und den Clean-Room-Regeln, ein eigenes `CLAUDE.md` und ein Release-Skript.
- **Neues Repository `mytracks/GPSLoggerKitGPL` (GPL-3.0-or-later, öffentlich):**
  - Aufbau wie bei GPSLoggerKit, mit dem Ordner `Packages/GPSLoggerKitGPL`.
  - Es hängt per Paket-URL und Version von GPSLoggerKit ab.
  - Sein `openspec/` enthält die Specs der portierten Formate und Geräteprotokolle und die Regeln für Portierungen.
- **gpsloader:**
  - **BREAKING (für die Entwicklung):** Die Ordner `Packages/GPSLoggerKit` und `Packages/GPSLoggerKitGPL` entfallen.
  - GPSLoaderKit bindet beide Pakete per URL ein, auf Versionen ab 0.1.0 bis vor 0.2.0. `Package.resolved` liegt im Repository, damit Release-Builds reproduzierbar sind.
  - GPSLoaderKit bleibt im Repository, weil es der interne Unterbau der App ist.
- **Releases auf GitHub:**
  - **Pakete:** Jedes Paket veröffentlicht Versionen als Git-Tag (`0.1.0`) mit einem GitHub-Release samt Release-Notes.
  - **App:** `Scripts/release.sh` legt auf Wunsch (eigene Option) das GitHub-Release an, mit Tag, Release-Notes, dem notarisierten ZIP und der Prüfsumme. Den Namen der App und des ZIP legt der Change `rename-and-icon` fest.
  - **Vorabversion:** Versionen unter 1.0.0 erscheinen auf GitHub als „Pre-release“.
- **OpenSpec:**
  - Die Specs ziehen mit dem Code in die neuen Repositories um und werden hier stillgelegt bzw. gekürzt. Die Zuordnung steht unter „Capabilities“.
  - Anforderungen an den Gerätekatalog der App und an die Transporte bleiben in gpsloader.
  - `openspec/config.yaml` wird aufgeteilt. Die 25 archivierten Changes bleiben hier als Historie.
- **Dokumentation:**
  - **`CLAUDE.md`, `README.md` und `config.yaml`:** Sie beschreiben die neue Aufteilung.
  - **„Vertrieb“ in `config.yaml`:** Die App wird über GitHub-Releases verteilt statt über die Website.
  - **Über-Fenster:** Es nennt als Quelle von GPSLoggerKit dessen Repository.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Geräte:** Keines kommt hinzu, keines entfällt.
- **Treiberfamilien:** Alle Familien ziehen mit ihrem Paket um, ohne dass sich das Verhalten ändert.
  - Nach GPSLoggerKit: NMEA, GPX, IGC, FIT, TCX, Suunto SML, KML/KMZ, CSV-Logger und GNS 2000.
  - Nach GPSLoggerKitGPL: SkyTraq, MTK/Holux, Wintec, Locosys/Navilink, i-GotU, Magellan, XAiOX iTrackU, Medion GoPal und Alan Map500.

## Berührte Vorschläge aus der Exploration

- **„Updates über Sparkle“:** nicht berührt. GitHub-Releases wären eine mögliche Quelle dafür; ob und wie Updates kommen, entscheidet ein eigener Change.

## Nicht im Umfang

- Einbinden von GPSLoggerKit in myTracks Neo. Das ist ein Change im Repository von myTracks Neo.
- Umbenennen der App und neues Icon (Change `rename-and-icon`).
- Update-Prüfung oder Sparkle.
- Automatische Builds und Tests auf GitHub (Actions).
- Eintrag in den Swift Package Index.
- Neue Formate oder Treiber; offen bleiben BG728 und WSG-2000 NAL.
- Ein Kontaktweg für Support-Pakete.

## Reihenfolge

1. **`rename-and-icon`** zuerst umsetzen, damit das erste GitHub-Release der App gleich „myTracks Loader“ heißt.
2. **Offene Changes archivieren:** `support-package`, `device-ports-and-hints` und `main-window-sections` vor diesem Change. Deren Specs bleiben in gpsloader, berühren die umziehenden Specs aber nicht.

## Capabilities

### New Capabilities

- `release-publishing`: Versionen, Git-Tags und GitHub-Releases der App und der beiden Pakete sowie die Einbindung der Pakete in die App per Version.

### Modified Capabilities

Ganz stillgelegt (ziehen nach `mytracks/GPSLoggerKit`):
- `logger-kit`, `nmea-import`, `gpx-import`, `igc-import`, `fit-import`, `tcx-import`, `suunto-import`, `kml-import`, `csv-logger-import`

Ganz stillgelegt (ziehen nach `mytracks/GPSLoggerKitGPL`):
- `logger-kit-gpl`, `skytraq-import`, `mtk-import`, `wintec-import`, `locosys-import`, `gopal-import`, `magellan-import`, `alan-import`

Gekürzt: Die Protokoll-Anforderungen ziehen mit dem Paket um. Hier bleiben die Anforderungen an den Gerätekatalog der App und an Transporte der App.
- `gns2000-device`: Bleibt „GNS 2000 im Katalog“, der Rest zieht nach GPSLoggerKit.
- `mtk-device`, `skytraq-device`, `wintec-device`, `navilink-device`, `magellan-device`, `itracku-device`: Bleibt „… im Katalog“, der Rest zieht nach GPSLoggerKitGPL.
- `igotu-device`: Bleiben „USB-HID-Verbindung“ (Modul HIDTransport) und „i-GotU-Geräte im Katalog“, der Rest zieht nach GPSLoggerKitGPL.

## Impact

- **Neue Repositories auf GitHub:** zwei öffentliche Repositories. Angelegt werden sie erst nach ausdrücklicher Freigabe des Entwicklers.
- **gpsloader:**
  - **Pakete:** `Packages/GPSLoggerKit` und `Packages/GPSLoggerKitGPL` werden entfernt.
  - **Abhängigkeiten:** `Packages/GPSLoaderKit/Package.swift` bekommt URL-Abhängigkeiten, dazu kommt `Package.resolved`.
  - **Projekt:** `project.yml` und das Testschema ändern sich.
  - **Skripte und Dokumente:** `Scripts/release.sh`, `README.md`, `CLAUDE.md` und `openspec/config.yaml`.
- **Entwicklung:** Wer Paket und App zugleich ändert, arbeitet mit einem lokal ausgecheckten Paket an Stelle der URL (Xcode-Override). Paketänderungen erreichen die App erst mit einem neuen Paket-Release.
- **Clean-Room:** Die Trennung von MIT- und GPL-Code wird zur Trennung der Repositories. Ein Change arbeitet je Repository an genau einem Paket.
