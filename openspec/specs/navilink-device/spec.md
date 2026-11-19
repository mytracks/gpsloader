# navilink-device Specification

## Purpose
Die Einträge der Locosys-Geräte im NAVILINK-Modus im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `navilink-device` dort).

## Requirements

### Requirement: Navilink-Geräte im Katalog
Der Gerätekatalog SHALL die sechs Navilink-Geräte der Alt-App mit 115200 Baud und ohne Löschen enthalten.

#### Scenario: Navilink-Geräte im Katalog
- **WHEN** der Anwender ein Navilink-Gerät wählt
- **THEN** ist „Speicher löschen …“ nicht verfügbar
