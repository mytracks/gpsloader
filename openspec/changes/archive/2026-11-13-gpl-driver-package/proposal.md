# Proposal: gpl-driver-package

## Why

Für mehrere Logger-Familien gibt es keine öffentliche Spezifikation, aber erprobte Implementierungen unter der GPL (gpsbabel, igotu2gpx u. a.). Bisher dürfen wir sie wegen der MIT-Lizenz von GPSLoggerKit nicht einmal lesen und müssen jedes Format aus Black-Box-Beobachtung rekonstruieren. Der Entwickler hat am 2026-11-10 entschieden, solche Portierungen zu erlauben, ohne GPSLoggerKit aufzugeben: GPSLoggerKit bleibt MIT und Clean-Room, portierter GPL-Code kommt in ein eigenes Paket, und die App steht insgesamt unter der GPL. Der Change schafft dafür den Rahmen, bevor die nächste Familie (SkyTraq) beginnt.

## What Changes

- **Neues Paket `GPSLoggerKitGPL`** unter `Packages/GPSLoggerKitGPL`, Lizenz GPL-3.0-or-later, nur macOS 12+. Es hängt nur von GPSLoggerKit und den Systembibliotheken ab und stellt einen eigenen Formatkatalog bereit, zunächst leer. Portierte Formate und Treiber kommen in späteren Changes dazu.
- **GPSLoggerKit: zusammensetzbarer Katalog.** Ein Katalog kann aus den eigenen Formaten und zusätzlichen Formaten anderer Pakete gebildet werden. Erkennung, Suche nach Kennung und Einlesen arbeiten auf diesem Katalog. Die bestehende API (`FileFormats.all`, `detect`, `read`) bleibt unverändert. GPSLoggerKit kennt das GPL-Paket nicht.
- **Dateimodus der App** verwendet den zusammengesetzten Katalog aus GPSLoggerKit und GPSLoggerKitGPL.
- **Lizenz der App:** Eigener Code der App, von GPSLoaderKit und RosettaInstaller steht unter GPL-3.0-or-later. Dazu kommen eine Lizenzdatei im Repository und Hinweise in den READMEs. GPSLoggerKit behält seine MIT-Lizenz.
- **Über-Fenster:** zeigt zusätzlich die Lizenz der App (GPL-3.0-or-later) mit Verweis auf ihren Quellcode, den MIT-Hinweis von GPSLoggerKit und die Urheber portierter Quellen. Das Bundle enthält den MIT-Text.
- **Regeln für Portierungen** in `openspec/config.yaml`, `CLAUDE.md` und den Paketdokumenten:
  - Zulässig sind nur Quellen, deren Lizenz mit GPL-3.0-or-later vereinbar ist.
  - Jede Portierung nennt Quelle, Version, Urheber und Lizenz und behält die Urheberhinweise.
  - Pro Familie wird entschieden, ob sie Clean-Room in GPSLoggerKit oder als Portierung in GPSLoggerKitGPL entsteht. Wurde für eine Familie GPL-Quelltext gelesen, darf sie nicht mehr in GPSLoggerKit umgesetzt werden.
  - Arbeit an GPSLoggerKit bleibt Clean-Room, der Agent liest dabei keinen GPL-Quelltext.

## Capabilities

### New Capabilities

- `logger-kit-gpl`: das Paket GPSLoggerKitGPL mit Lizenz, Plattform, Abhängigkeiten, Formatkatalog, zulässigen Quellen und Herkunftsnachweis portierter Formate.

### Modified Capabilities

- `logger-kit`: neue Anforderung „Erweiterbarer Formatkatalog“. Die Formaterkennung arbeitet auch mit einem zusammengesetzten Katalog.
- `file-conversion`: „Unterstützte Formate“ bezieht sich auf den Katalog der App, also GPSLoggerKit plus GPSLoggerKitGPL.
- `app-shell`: „Lizenzhinweise“ nennt auch die Lizenz der App, die Bezugsquelle ihres Quellcodes, GPSLoggerKit (MIT) und die Urheber portierter Quellen.

## Betroffene Geräte und Treiberfamilien

Keine Geräte direkt. Der Change ändert nur, wo künftige Treiber entstehen dürfen. Kandidaten für eine Portierung sind die Familien ohne öffentliche Spezifikation: i-GotU (igotu2gpx) und Wintec (gpsbabel `wbt`). Die Entscheidung fällt jeweils im Proposal der Familie.

Für WSG-2000 NAL gilt: `wsg2000.c` steht unter einer eigenen CC-BY-SA-ähnlichen Lizenz mit Zusatzbedingungen. Eine GPL-Freigabe gibt es dort nur als Absichtserklärung („will also release this under GPLv2 if I must“). Das ist keine mit GPL-3.0-or-later vereinbare Lizenz. NAL bleibt deshalb Black-Box, solange der Autor keine passende Lizenz erteilt.

## Nicht im Umfang

- Portierung eines konkreten Formats oder Treibers. Jede Familie bekommt ihren eigenen Change.
- Änderung der Reihenfolge der Familien in `config.yaml`.
- iOS-Unterstützung von GPSLoggerKitGPL. App-Store-Bedingungen und GPL vertragen sich nicht. GPSLoggerKit bleibt das Paket für iOS.
- Auslagerung von GPSLoggerKitGPL in ein eigenes Repository.
- Lizenzkopf in jeder eigenen Quelldatei. Eigener Code wird über die Lizenzdateien gekennzeichnet. Nur portierte Dateien bekommen einen Kopf mit den Urhebern der Vorlage.
- Veröffentlichung des Quellcodes (Repository oder Archiv auf der Website). Sie muss vor der ersten Auslieferung erfolgen, ist aber Aufgabe des Entwicklers. Der Change sieht dafür eine konfigurierbare Adresse im Über-Fenster vor.
- Rechtliche Prüfung. Der Change setzt die Entscheidung des Entwicklers um, er ersetzt keine Rechtsberatung.

## Impact

- **Neu:** `Packages/GPSLoggerKitGPL` (Package.swift, LICENSE, PROVENANCE.md, README.md, Katalog, Tests).
- **GPSLoggerKit:** neuer Katalogtyp, `FileFormats` delegiert darauf. Rein additive API.
- **GPSLoaderKit:** `FileConversion` nimmt einen Katalog entgegen und hängt zusätzlich von GPSLoggerKitGPL ab.
- **App:** Katalog in `AppEnvironment`, Über-Fenster, Lizenztexte im Bundle (MIT), `project.yml`, `Scripts/verify-bundle.sh`.
- **Dokumentation und Regeln:** `LICENSE` im Wurzelverzeichnis, `README.md`, `CLAUDE.md`, `openspec/config.yaml`, README von GPSLoggerKit (Clean-Room-Abschnitt nennt das GPL-Paket als Ort für Portierungen).
- **Kein Einfluss** auf gpsbabel, Rosetta, Treiber, Gerätekatalog und Ausgabeformat.
