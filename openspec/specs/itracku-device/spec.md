# itracku-device Specification

## Purpose
Der Eintrag des XAiOX iTrackU im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `itracku-device` dort).

## Requirements

### Requirement: iTrackU im Katalog
Der Gerätekatalog SHALL den Eintrag „XAiOX iTrackU“ mit 4800 Baud und ohne Löschen enthalten.

#### Scenario: iTrackU wählen
- **WHEN** der Anwender „XAiOX iTrackU“ wählt
- **THEN** ist „Speicher löschen …“ nicht verfügbar
