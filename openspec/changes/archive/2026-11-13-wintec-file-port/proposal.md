# Proposal: Wintec-Dateien (wintec_tes, wbt-bin, wbt-tk1) als Portierung in GPSLoggerKitGPL

## Why

Wintec-Logger hinterlassen Dateien in drei Formaten, die der Dateimodus bisher nicht lesen kann:

| Format | Geräte | Herkunft der Datei |
|---|---|---|
| `.tes` | WBT-202 | schreibt sie auf seine SD-Karte |
| `.bin` | WBT-100/200 | Speicherabbild aus der Hersteller-Software bzw. gpsbabel |
| `.tk1` | WBT-201, G-Rays 2, WSG-1000 | Exportformat des Herstellers |

Eine öffentliche Spezifikation gibt es nicht. gpsbabel ab Version 1.8 kennt die Formate nicht mehr (`docs/legacy-analysis.md`, Abschnitt 3). Am 2026-11-13 hat der Entwickler entschieden, alles Mögliche ins GPL-Paket zu portieren.

## What Changes

- **Neue Formate in GPSLoggerKitGPL, nur macOS,** übersetzt aus gpsbabel 1.7.0 nach Swift:
  - `wintec-tes` (Endung `.tes`), Vorlage `wintec_tes.cc`;
  - `wbt-bin` (Endung `.bin`) und `wbt-tk1` (Endung `.tk1`), Vorlage `wbt-200.cc`, nur der Dateileser.
- **Inhalt:** Positionen, Zeiten, Höhen, Track-Aufteilung und Wegpunkte (Taste) folgen der Vorlage.
- **Katalog und Herkunft:**
  - `GPLFileFormats.all` enthält die drei Formate.
  - Der gpsbabel-Eintrag in `credits` nennt zusätzlich die Urheber der Vorlagen.
  - `PROVENANCE.md` bekommt drei Abschnitte.

## Zuordnung der Familie

- **Familie Wintec:** GPSLoggerKitGPL (Portierung), Entscheidung des Entwicklers vom 2026-11-13, bereits in `openspec/config.yaml` eingetragen.
- **Vorlagen:** gpsbabel, Tag `gpsbabel_1_7_0`:
  - `wintec_tes.cc`: Copyright (C) 2010 Robert Lipe, GPL-2.0-or-later, Zeilen 7–10.
  - `wbt-200.cc`: Copyright (C) 2006 Andy Armstrong, GPL-2.0-or-later, Zeilen 6–9.
- **Leseregel:** Gelesen werden nur diese beiden Dateien und, soweit nötig, die dort benutzten gemeinsamen Hilfen von gpsbabel.

## Capabilities

### New Capabilities

- `wintec-import`: Dateien der Wintec-Logger (TES, BIN, TK1) einlesen und daraus Tracks und Wegpunkte bilden.

### Modified Capabilities

- `logger-kit-gpl`: Der Katalog des Pakets enthält zusätzlich `wintec-tes`, `wbt-bin` und `wbt-tk1`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Datei-Gerät mit Treiber `wintec_tes`:** „Wintec WBT-202 (using SD card)“.
- **Treiber `wbt`, nur über eine Datei:** G-Rays 2, Wintec WBT-100, WBT-200, WBT-201 und WSG-1000 (G-Tender). Ihr direktes Auslesen ist nicht Teil dieses Changes.

## Nicht im Umfang

- **Direktes Auslesen und Löschen** (gpsbabel `wbt`): Dafür fehlt die Treiber-Anbindung des GPL-Pakets, das kommt in einen eigenen Change.
- **Wintec WPL 1000 / Navilock NL-456DL:** Laut `config.yaml` ist das ein zurückgestellter Vorschlag.
- **iOS.**
- **Echte Dateien als Fixtures:** Es gibt nur synthetische Dateien, gegengeprüft mit dem gpsbabel-1.7.0-Binary.

## Impact

- **Neue Dateien:** `Packages/GPSLoggerKitGPL/Sources/GPSLoggerKitGPL/Wintec/`, Lokalisierung, Test-Encoder und Fixtures.
- **App:** Ihr Code bleibt unverändert, das Hauptfenster listet 15 Formate.
- **Dokumentation:** `PROVENANCE.md` und `README.md` des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` werden ergänzt.
