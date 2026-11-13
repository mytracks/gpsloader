# Proposal: SkyTraq-Logger direkt auslesen (Portierung)

## Why

SkyTraq-Venus-Logger (Canmore GT-730FL/GT-740FL/GT-750F, Navin MiniHomer u. a.) waren in myTracks über den gpsbabel-Treiber `skytraq` auslesbar. gpsloader kann bisher nur ihre Speicherabbilder als Datei lesen (Change `skytraq-bin-port`). Der Entwickler hat am 2026-11-13 beauftragt, auch das direkte Auslesen umzusetzen. Die Familie ist dem GPL-Paket zugeordnet.

## What Changes

- **`SkyTraqDevice` in GPSLoggerKitGPL:** übersetzt aus dem seriellen Teil von gpsbabel 1.7.0 `skytraq.cc`, auf der Schnittstelle `DeviceConnection` aus dem Change `device-mode`.
  - **Baudrate:** Sie wird gesucht (Versionsabfrage), danach wird auf die Download-Rate umgeschaltet.
  - **Lesen:** Der Logstatus wird abgefragt, die Sektoren werden mehrfach gelesen. Bei NACK wird auf Einzel-Lesen ausgewichen.
  - **Auswertung:** Dekodiert wird mit dem Leser aus `skytraq-bin-port`.
  - **Abschluss:** Die alte Baudrate wird wiederhergestellt, danach startet das Gerät neu.
  - **Löschen** des Speichers.
- **Gerätekatalog:** elf SkyTraq-Geräte mit den Baudraten der Alt-App.
- **Debug-Automatisierung:** `-DebugReadDevice` (aus `device-mode`) dient für Ende-zu-Ende-Tests gegen ein simuliertes Gerät am Pseudo-Terminal.

## Zuordnung der Familie

SkyTraq: GPSLoggerKitGPL, Entscheidung des Entwicklers vom 2026-11-13. Vorlage `skytraq.cc` (Tag `gpsbabel_1_7_0`), Copyright (C) 2008–2019 Mathias Adam, GPL-2.0-or-later (Zeilen 11–14).

## Capabilities

### New Capabilities

- `skytraq-device`: SkyTraq-Venus-Logger über die serielle Schnittstelle auslesen und löschen.

### Modified Capabilities

(keine)

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

Alle Einträge mit Treiber `skytraq`:
- Canmore GT-730FL, GT-740FL und GT-750F;
- Conrad GPS-Datenlogger GT-730 und GT-750;
- Dörr GPS Photo Logger, Gisteq PhotoTrackr mini (DPL900), Navin MiniHomer;
- SkyTraq Venus, Travel Honey, Ventus GPS Route Logger G730.

## Nicht im Umfang

- **Optionen der Vorlage:** Zielort setzen (`targetlocation`), Logging konfigurieren (`configlog`), POI des MiniHomer, `first-sector`/`last-sector`, `dump-file` und `no-output`.
- **Test mit echter Hardware:** Er bleibt ein manueller Task.

## Impact

- **GPSLoggerKitGPL:** `SkyTraq/SkyTraqDevice.swift`. Dazu bekommt `SkyTraqDump.read` einen Parameter für die Endregel des Downloads.
- **GPSLoaderKit:** `DeviceDrivers/Families/SkyTraqDevices.swift`.
- **App:** Die Gerätewahl zeigt die SkyTraq-Geräte.
