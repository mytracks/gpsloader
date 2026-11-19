# mtk-device Specification

## Purpose
The entries of the MTK loggers (iBlue 747, Qstarz and others) and of the Holux M-241 and GPSport 245 in the app's device catalog. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `mtk-device` there).

## Requirements

### Requirement: MTK devices in the catalog
The device catalog SHALL contain the MTK devices of the old app with 115200 baud and the Holux devices with 38400 baud and SHALL offer erasing.

#### Scenario: MTK devices in the catalog
- **WHEN** the user opens the device list
- **THEN** it contains nine MTK and two Holux devices
