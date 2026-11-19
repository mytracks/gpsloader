# skytraq-device Specification

## Purpose
Die Einträge der Logger mit SkyTraq-Venus-Chipsatz im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `skytraq-device` dort).

## Requirements

### Requirement: SkyTraq-Geräte im Katalog
Der Gerätekatalog SHALL die SkyTraq-Geräte der Alt-App mit deren Baudraten enthalten (Anfangsrate und Download-Rate, Standard 230400) und Löschen anbieten.

#### Scenario: Geräte im Katalog
- **WHEN** der Anwender die Geräteliste öffnet
- **THEN** enthält sie die elf SkyTraq-Geräte, und „Canmore GT-750F“ arbeitet mit 38400 Baud
