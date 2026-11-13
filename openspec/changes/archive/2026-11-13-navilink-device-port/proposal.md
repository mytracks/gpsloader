# Proposal: Navilink-Geräte direkt auslesen (Portierung)

## Why

Locosys-Geräte im NAVILINK-Modus (GT-11, GT-31, BGT-31, NaviGPS) wurden in myTracks über gpsbabel `navilink` ausgelesen. gpsbabel ab 1.8 kennt den Treiber nicht mehr. Der Entwickler hat am 2026-11-13 das direkte Auslesen beauftragt. Die Familie ist dem GPL-Paket zugeordnet.

## What Changes

- **`NavilinkDevice` in GPSLoggerKitGPL**, übersetzt aus gpsbabel 1.7.0 `navilink.cc`:
  - Verbindung mit 115200 Baud, Synchronisation, Geräteinformation;
  - Wegpunkte lesen (je 32);
  - Tracklog lesen (je 512 Punkte, jeweils quittiert).
- **Gerätekatalog:** sechs Navilink-Geräte, ohne Löschen. Löschen bot auch die Alt-App für Navilink nicht an (`docs/legacy-analysis.md`, Abschnitt 2).

## Zuordnung der Familie

Navilink/Locosys: GPSLoggerKitGPL, Entscheidung des Entwicklers vom 2026-11-13. Vorlage `navilink.cc` (Tag `gpsbabel_1_7_0`), Copyright (C) 2007 Tom Hughes und (C) 2008 Rodney Lorrimar, GPL-2.0-or-later (Zeilen 7–10).

## Capabilities

### New Capabilities

- `navilink-device`: Wegpunkte und Tracklog von Navilink-Geräten über die serielle Schnittstelle lesen.

### Modified Capabilities

(keine)

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

Treiber `navilink` (USB und Bluetooth): Locosys BGT-31, GT-11 und GT-31, NaviGPS, NaviGPS-BT und „Navilink - generic“.

## Nicht im Umfang

- **Routen, Schreiben und Löschen:** `nuketrk`, `nukerte`, `nukewpt`, `nukedlg`.
- **Ausschalten:** `poweroff`.
- **Datenlogger-Puffer:** `datalog`. Die Alt-App nutzte ihn nicht, seine Dateien liest `locosys-file-port` (SBP).

## Impact

- **GPSLoggerKitGPL:** `Locosys/NavilinkDevice.swift`.
- **GPSLoaderKit:** `DeviceDrivers/Families/NavilinkDevices.swift`.
