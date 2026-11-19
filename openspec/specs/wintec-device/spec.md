# wintec-device Specification

## Purpose
The entries of the Wintec loggers in the app's device catalog. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `wintec-device` there).

## Requirements

### Requirement: Wintec devices in the catalog
The device catalog SHALL contain the five Wintec devices of the old app with one shared driver and SHALL offer erasing.

#### Scenario: Wintec devices in the catalog
- **WHEN** the user opens the device list
- **THEN** it contains G-Rays 2, WBT-100, WBT-200, WBT-201 and WSG-1000
