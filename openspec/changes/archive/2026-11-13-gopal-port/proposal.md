# Proposal: Medion-GoPal-Tracks (.trk) als Portierung in GPSLoggerKitGPL

## Why

Navigationsgeräte von Medion mit der Software GoPal zeichnen Tracks als Textdateien `.trk` auf. Die Alt-App las sie über gpsbabel (`gopal`). Der Dateimodus kann sie bisher nicht lesen. Eine öffentliche Beschreibung oder Beispieldateien gibt es nicht. Eine Black-Box-Beobachtung scheiterte, weil gpsbabel 1.7.0 aus einer GPX-Datei eine leere `.trk` schreibt (siehe Change `csv-logger-import`). Am 2026-11-13 hat der Entwickler entschieden, alles Mögliche ins GPL-Paket zu portieren.

## What Changes

- **Neues Format `gopal` (Endung `.trk`)** in GPSLoggerKitGPL, nur macOS. Es ist eine Übersetzung des Lesers aus gpsbabel 1.7.0 (`gopal.cc`) nach Swift.
- **Inhalt:** Positionen, Zeiten, Höhen, Geschwindigkeit und die Plausibilitätsprüfung der Zeilen folgen der Vorlage.
- **Katalog und Herkunft:**
  - `GPLFileFormats.all` enthält das Format.
  - Der gpsbabel-Eintrag in `credits` nennt zusätzlich den Urheber der Vorlage.
  - `PROVENANCE.md` bekommt einen Abschnitt.

## Zuordnung der Familie

- **Familie Medion GoPal:** GPSLoggerKitGPL (Portierung), Entscheidung des Entwicklers vom 2026-11-13, bereits in `openspec/config.yaml` eingetragen.
- **Abgrenzung zu den CSV-Loggern:** `config.yaml` führte GoPal zuvor zusammen mit V-900 und iBlue-CSV als „CSV-Logger“. Diese sind clean-room in GPSLoggerKit umgesetzt. GoPal ist ein eigenes Format eines anderen Herstellers ohne gemeinsamen Code und wird deshalb als eigene Familie geführt. `gopal.cc` enthält nichts zu V-900 oder iBlue, und dieser Change berührt GPSLoggerKit nicht.
- **Vorlage:** gpsbabel, Tag `gpsbabel_1_7_0`, Datei `gopal.cc`. Copyright (C) 2008 Dr. Jürgen Neumann und (C) 2005 Robert Lipe. Lizenz GPL-2.0-or-later (Zeilen 8–11).
- **Leseregel:** Gelesen wird nur `gopal.cc` und, soweit nötig, die dort benutzten gemeinsamen Hilfen.

## Capabilities

### New Capabilities

- `gopal-import`: GoPal-Trackdateien einlesen und daraus Tracks bilden.

### Modified Capabilities

- `logger-kit-gpl`: Der Katalog des Pakets enthält zusätzlich `gopal`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Datei-Gerät mit Treiber `gopal`:** Medion GoPAL.

## Nicht im Umfang

- **Optionen der Vorlage:** `date`, `maxspeed`, `minspeed` und `clean`. Die Standardwerte werden fest übernommen, soweit die Vorlage sie beim Lesen anwendet.
- **GoPal-Ausgabe:** Das Paket schreibt nur GPX.
- **iOS.**
- **Echte Dateien als Fixtures:** Es gibt nur synthetische Dateien, gegengeprüft mit dem gpsbabel-1.7.0-Binary (`-i gopal`).

## Impact

- **Neue Dateien:** `Packages/GPSLoggerKitGPL/Sources/GPSLoggerKitGPL/GoPal/`, Lokalisierung, Tests und eine Fixture.
- **App:** Ihr Code bleibt unverändert, das Hauptfenster listet 18 Formate.
- **Dokumentation:** `PROVENANCE.md` und README des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` werden ergänzt.
