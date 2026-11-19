# wintec-device Specification

## Purpose
Die Einträge der Wintec-Logger im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `wintec-device` dort).

## Requirements

### Requirement: Wintec-Geräte im Katalog
Der Gerätekatalog SHALL die fünf Wintec-Geräte der Alt-App mit einem gemeinsamen Treiber enthalten und Löschen anbieten.

#### Scenario: Wintec-Geräte im Katalog
- **WHEN** der Anwender die Geräteliste öffnet
- **THEN** enthält sie G-Rays 2, WBT-100, WBT-200, WBT-201 und WSG-1000
