# skytraq-device Specification

## Purpose
The entries of the loggers with a SkyTraq Venus chipset in the app's device catalog. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `skytraq-device` there).

## Requirements

### Requirement: SkyTraq devices in the catalog
The device catalog SHALL contain the SkyTraq devices of the old app with their baud rates (initial rate and download rate, default 230400) and SHALL offer erasing.

#### Scenario: Devices in the catalog
- **WHEN** the user opens the device list
- **THEN** it contains the eleven SkyTraq devices, and "Canmore GT-750F" works with 38400 baud
