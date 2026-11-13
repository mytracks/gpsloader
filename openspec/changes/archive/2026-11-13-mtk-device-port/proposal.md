# Proposal: MTK-Logger direkt auslesen (Portierung)

## Why

MTK-Logger (iBlue 747, Qstarz BT-Q1000/BT-Q1300/BT-100, Holux M-241/GPSport 245 u. a.) sind die größte Gruppe im Gerätekatalog der Alt-App. Sie wurden über gpsbabel `mtk` bzw. `m241` ausgelesen. gpsloader liest bisher nur ihre Speicherabbilder als Datei (`mtk-bin-port`). Der Entwickler hat am 2026-11-13 das direkte Auslesen beauftragt. Die Familie ist dem GPL-Paket zugeordnet.

## What Changes

- **`MTKDevice` in GPSLoggerKitGPL**, übersetzt aus dem seriellen Teil von gpsbabel 1.7.0 `mtk_logger.cc`:
  - Modellabfrage (`$PMTK605`), bei Holux GR-245 der zusätzliche Handshake.
  - Logstatus abfragen, Logging pausieren, Flash-Belegung abfragen (sonst nach 64-KiB-Blöcken suchen).
  - Blöcke zu 1 KiB lesen (`$PMTK182,7`, Antwort `$PMTK182,8` hexkodiert).
  - Das Abbild mit dem Leser aus `mtk-bin-port` dekodieren und das Logging wieder einschalten.
  - Löschen (`$PMTK182,6,1`).
- **Gerätekatalog:** neun MTK-Geräte (115200 Baud) und zwei Holux-Geräte (38400 Baud).

## Zuordnung der Familie

MTK: GPSLoggerKitGPL, Entscheidung des Entwicklers vom 2026-11-13. Vorlage `mtk_logger.cc` (Tag `gpsbabel_1_7_0`), Copyright (C) 2007 Per Borgentun, GPL-2.0-or-later (Zeilen 8–11).

## Capabilities

### New Capabilities

- `mtk-device`: MTK- und Holux-Logger über die serielle Schnittstelle auslesen und löschen.

### Modified Capabilities

(keine)

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Treiber `mtk`:** Blumax GPS-4044, iBlue 747, iTrek Z1, Networx iGeo, Photomate 887, QStarz BT-100, Qstarz BT-Q1000, Qstarz BT-Q1300 und Transystem 860E.
- **Treiber `m241`:** Holux M-241 und Holux GPSport 245.
- **Nicht übernommen:** „Holux GPSport 245 – alternative“ (Shell-Kommando). Es ist mit dem Eintrag Holux GPSport 245 abgedeckt (offener Vorschlag in `config.yaml`).

## Nicht im Umfang

- **Optionen der Vorlage:** `erase_only`, `log_enable`, `csv` und `block_size_kb`.
- **Zwischenspeicher:** der Abgleich mit einem früheren `data.bin` (`init_scan` mit Cache).

## Impact

- **GPSLoggerKitGPL:** `MTK/MTKDevice.swift`.
- **GPSLoaderKit:** `DeviceDrivers/Families/MTKDevices.swift`.
- **App:** Die Gerätewahl zeigt die MTK- und Holux-Geräte.
