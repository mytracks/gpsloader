# itracku-device Specification

## Purpose
The entry of the XAiOX iTrackU in the app's device catalog. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `itracku-device` there).

## Requirements

### Requirement: iTrackU in the catalog
The device catalog SHALL contain the entry "XAiOX iTrackU" with 4800 baud and without erasing.

#### Scenario: Choose iTrackU
- **WHEN** the user chooses "XAiOX iTrackU"
- **THEN** "Erase Memory…" is not available
