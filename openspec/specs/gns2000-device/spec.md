# gns2000-device Specification

## Purpose
The entry of the Bluetooth logger GNS 2000 (also GNS 2000 plus) in the app's device catalog. The device protocol lives in GPSLoggerKit (https://github.com/mytracks/GPSLoggerKit, spec `gns2000-device` there).

## Requirements

### Requirement: GNS 2000 in the catalog
The device catalog SHALL contain an entry "GNS 2000" with the connection type Bluetooth. It applies to the device names "GNS 2000" and "GNS 2000 plus" and the SDP service "GNS GPS". It SHALL need no port choice and SHALL offer erasing.

#### Scenario: Choose GNS 2000
- **WHEN** the user chooses "GNS 2000"
- **THEN** the window shows no port choice, and "Read" and "Erase Memory…" are available
