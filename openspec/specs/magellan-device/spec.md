# magellan-device Specification

## Purpose
The entries of the serial Magellan devices in the app's device catalog. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `magellan-device` there).

## Requirements

### Requirement: Magellan devices in the catalog
The device catalog SHALL contain the seven serial Magellan devices of the old app with 4800 baud and without erasing.

#### Scenario: Choose a Magellan device
- **WHEN** the user chooses "Magellan SporTrak Map"
- **THEN** "Erase Memory…" is not available
