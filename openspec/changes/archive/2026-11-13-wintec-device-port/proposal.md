# Proposal: Wintec-Logger direkt auslesen (Portierung)

## Why

Wintec WBT-100/200/201, G-Rays 2 und WSG-1000 wurden in myTracks über den gpsbabel-Treiber `wbt` ausgelesen. gpsbabel ab 1.8 kennt ihn nicht mehr, gpsloader liest bisher nur Wintec-Dateien (`wintec-file-port`). Der Entwickler hat am 2026-11-13 das direkte Auslesen beauftragt. Die Familie ist dem GPL-Paket zugeordnet.

## What Changes

- **`WintecDevice` in GPSLoggerKitGPL**, übersetzt aus dem seriellen Teil von gpsbabel 1.7.0 `wbt-200.cc`:
  - **Gerätetyp:** wird automatisch erkannt. WBT-200 antwortet mit 9600 Baud auf `$PFST`, WBT-201 mit 57600 Baud auf `@AL`, WSG-1000 auf `@AL,2,3`.
  - **WBT-200:** `READLOGGER` liefert die Datensätze roh; die Satzlänge erkennt der Treiber wie bei `wbt-bin`.
  - **WBT-201 und WSG-1000:** Der Treiber liest Stücke zu 4 KiB mit Prüfsumme, auch über das Ende des Ringpuffers hinweg. Dekodiert wird wie bei `wbt-tk1`.
  - **Löschen:** für beide Varianten.
- **Gerätekatalog:** fünf Wintec-Geräte.

## Zuordnung der Familie

Wintec: GPSLoggerKitGPL, Entscheidung des Entwicklers vom 2026-11-13. Vorlage `wbt-200.cc` (Tag `gpsbabel_1_7_0`), Copyright (C) 2006 Andy Armstrong, GPL-2.0-or-later (Zeilen 6–9).

## Capabilities

### New Capabilities

- `wintec-device`: Wintec-Logger über die serielle Schnittstelle auslesen und löschen.

### Modified Capabilities

(keine)

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

Treiber `wbt` (USB und Bluetooth): G-Rays 2, Wintec WBT-100, WBT-200, WBT-201 und WSG-1000 (G-Tender).

## Nicht im Umfang

- **WBT-202 (TES-Dateien) und WPL 1000:** Den WBT-202 deckt `wintec-file-port` über seine TES-Dateien ab, den WPL 1000 ein zurückgestellter Vorschlag.

## Impact

- **GPSLoggerKitGPL:** `Wintec/WintecDevice.swift`. In `WintecFileFormats.swift` wird `readWBT201Records` als wiederverwendbarer Teil des TK1-Lesers herausgelöst.
- **GPSLoaderKit:** `DeviceDrivers/Families/WintecDevices.swift`.
