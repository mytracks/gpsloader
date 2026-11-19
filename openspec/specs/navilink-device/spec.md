# navilink-device Specification

## Purpose
The entries of the Locosys devices in NAVILINK mode in the app's device catalog. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `navilink-device` there).

## Requirements

### Requirement: Navilink devices in the catalog
The device catalog SHALL contain the six Navilink devices of the old app with 115200 baud and without erasing.

#### Scenario: Navilink devices in the catalog
- **WHEN** the user chooses a Navilink device
- **THEN** "Erase Memory…" is not available
