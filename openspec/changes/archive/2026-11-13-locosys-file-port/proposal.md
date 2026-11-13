# Proposal: Locosys-Dateien (sbp, sbn) als Portierung in GPSLoggerKitGPL

## Why

Locosys-Logger (GT-11, BGT-11, GT-31, BGT-31, NaviGPS) schreiben ihre Aufzeichnungen als `.sbp` (Datenlogger) und `.sbn` (SiRF-Binärprotokoll) auf eine Speicherkarte oder übergeben sie per USB. Der Dateimodus kann diese Dateien bisher nicht lesen. `openspec/config.yaml` sah vor, sie weiterhin über gpsbabel zu lesen. Den Dateimodus erreicht dieser Weg aber nicht, weil der Dateimodus bewusst kein gpsbabel nutzt. Am 2026-11-13 hat der Entwickler entschieden, alles Mögliche ins GPL-Paket zu portieren. Darunter fallen auch diese beiden Formate.

## What Changes

- **Neue Formate in GPSLoggerKitGPL, nur macOS,** übersetzt aus gpsbabel 1.7.0 nach Swift:
  - `sbp` (Endung `.sbp`), Vorlagen `sbp.cc` und die Dekodierung der Logpunkte aus `navilink.cc`;
  - `sbn` (Endung `.sbn`), Vorlage `sbn.cc`.
- **Inhalt:** Positionen, Zeiten, Höhen, Geschwindigkeit, Kurs, DOP und Satelliten folgen der Vorlage.
- **Katalog und Herkunft:**
  - `GPLFileFormats.all` enthält beide Formate.
  - Der gpsbabel-Eintrag in `credits` nennt zusätzlich die Urheber der Vorlagen.
  - `PROVENANCE.md` bekommt zwei Abschnitte.
- **`openspec/config.yaml`:** SBP/SBN wandern aus „Weiterhin über gpsbabel“ in die portierten Formate.

## Zuordnung der Familie

- **Familie Navilink/Locosys:** GPSLoggerKitGPL (Portierung), Entscheidung des Entwicklers vom 2026-11-13, bereits in `openspec/config.yaml` eingetragen.
- **Vorlagen** (gpsbabel, Tag `gpsbabel_1_7_0`), alle unter GPL-2.0-or-later, jeweils Zeilen 7–10 bzw. 8–11:
  - `sbp.cc` und `sbn.cc`: Copyright (C) 2008 Rodney Lorrimar und (C) 2005 Robert Lipe.
  - `navilink.cc` und `navilink.h`: Copyright (C) 2007 Tom Hughes und (C) 2008 Rodney Lorrimar bzw. Robert Lipe.
- **Leseregel:** Gelesen werden nur diese Dateien und, soweit nötig, die dort benutzten gemeinsamen Hilfen.

## Capabilities

### New Capabilities

- `locosys-import`: SBP- und SBN-Dateien der Locosys-Logger einlesen und daraus Tracks bilden.

### Modified Capabilities

- `logger-kit-gpl`: Der Katalog des Pakets enthält zusätzlich `sbp` und `sbn`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Datei-Geräte mit Treiber `sbn` bzw. `sbp`:** „Locosys/NaviGPS GT-11/BGT-11/T-31/BGT-31 SiRF binary logfile (.sbn)“ und „Locosys/NaviGPS GT-11/BGT-11/GT-31/BGT-31 datalogger (.sbp)“.
- **Treiber `navilink`, nur über eine Datei:** Locosys BGT-31, GT-11, GT-31, NaviGPS und NaviGPS-BT. Ihr direktes Auslesen ist nicht Teil dieses Changes.

## Nicht im Umfang

- **Direktes Auslesen, Schreiben und Löschen** über das Navilink-Protokoll: Dafür fehlt die Treiber-Anbindung des GPL-Pakets.
- **Wegpunkte und Routen des Navilink-Geräts:** Sie kommen nur über den seriellen Treiber.
- **iOS.**
- **Echte Dateien als Fixtures:** Es gibt nur synthetische Dateien, gegengeprüft mit dem gpsbabel-1.7.0-Binary.

## Impact

- **Neue Dateien:** `Packages/GPSLoggerKitGPL/Sources/GPSLoggerKitGPL/Locosys/`, Lokalisierung, Test-Encoder und Fixtures.
- **App:** Ihr Code bleibt unverändert, das Hauptfenster listet 17 Formate.
- **Dokumentation:** `PROVENANCE.md` und README des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` werden ergänzt.
