# magellan-device Specification

## Purpose
Die Einträge der seriellen Magellan-Geräte im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `magellan-device` dort).

## Requirements

### Requirement: Magellan-Geräte im Katalog
Der Gerätekatalog SHALL die sieben seriellen Magellan-Geräte der Alt-App mit 4800 Baud und ohne Löschen enthalten.

#### Scenario: Magellan-Gerät wählen
- **WHEN** der Anwender „Magellan SporTrak Map“ wählt
- **THEN** ist „Speicher löschen …“ nicht verfügbar
