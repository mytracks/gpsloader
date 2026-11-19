# igotu-device Specification

## Purpose
The i-GotU loggers in the app: their entries in the device catalog and the USB HID connection of the USB models. The device protocol lives in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, spec `igotu-device` there).

## Requirements

### Requirement: USB HID connection
For USB models the app SHALL find the device by vendor and product ID (`0x0DF7`/`0x0900`), open it exclusively, send commands as 8-byte output reports and read answers from the input reports, with a timeout and diagnostic capture. If no device is connected, the operation MUST end with "device not found".

#### Scenario: No i-GotU connected
- **WHEN** the user reads a USB model and no device is connected
- **THEN** the app reports that the device was not found

### Requirement: i-GotU devices in the catalog
The device catalog SHALL contain the five USB models without port choice and the GT-800 and GT-800 Pro with a serial port.

#### Scenario: i-GotU devices in the catalog
- **WHEN** the user chooses a USB model
- **THEN** the window shows no port choice
