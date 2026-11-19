# device-mode Specification

## Purpose
The direct mode of myTracks Loader: choosing device and port in the main window, starting reading and erasing, the device catalog of all native drivers and their connection to the session, over a serial port, USB HID or Bluetooth.

## Requirements

### Requirement: Choose the device
The main window SHALL offer a choice of all devices of the device catalog in the section "Read Device", sorted alphabetically. The last chosen combination of device and port SHALL be preselected at the next start, if both still exist.

#### Scenario: Remember the choice
- **WHEN** the user chooses "Qstarz BT-Q1000" and `/dev/cu.usbserial-1410` and restarts the app
- **THEN** device and port are chosen again, if the port exists

### Requirement: Choose the port
For serial devices the window SHALL show the ports `/dev/cu.*` without system ports and with readable names (USB: product or chip vendor; Bluetooth: "Bluetooth:" and the device name; the path as tooltip). A port that fits the device SHALL be at the top and preselected, then USB ports, then Bluetooth ports. The list SHALL stay current when devices are plugged in and out. Without a port the window SHALL say so and not offer reading. Other devices have no port choice.

#### Scenario: Logger plugged in
- **WHEN** the user plugs in a USB logger while the window is open
- **THEN** its port appears in the list

#### Scenario: No port
- **WHEN** a serial device is chosen and there is no port
- **THEN** "Read" is disabled, and a hint names the reason

#### Scenario: Fitting Bluetooth port
- **WHEN** "Holux M-241" is chosen and the ports `/dev/cu.usbserial-1410` and `/dev/cu.HOLUX_M-241-SPPSlave` exist
- **THEN** "Bluetooth: HOLUX_M-241-SPPSlave" is at the top and preselected

#### Scenario: System ports
- **WHEN** only `/dev/cu.Bluetooth-Incoming-Port` and `/dev/cu.debug-console` exist
- **THEN** the list is empty, and the hint "no port" appears

### Requirement: Start reading and erasing
"Read" SHALL start the driver of the chosen device with the chosen port through the session (`logger-session`). "Erase Memory…" SHALL only be offered for devices whose driver can erase, and SHALL first get the confirmation of the session. While an operation runs, neither button SHALL start a second operation.

#### Scenario: Device without erasing
- **WHEN** a device is chosen whose driver cannot erase
- **THEN** "Erase Memory…" is not available

### Requirement: Device catalog
For each device the device catalog SHALL define the name, the driver, the connection type (serial, USB HID or Bluetooth RFCOMM), the baud rate or the device names and service, and the erase support. It SHALL contain only devices whose driver exists.

#### Scenario: Driver missing
- **WHEN** a family has no driver yet
- **THEN** its devices do not appear in the choice

#### Scenario: Bluetooth device
- **WHEN** the user chooses a device with the connection type Bluetooth RFCOMM
- **THEN** there is no port choice, and "Read" is available without a port

### Requirement: Connecting the drivers
A driver from GPSLoggerKit or GPSLoggerKitGPL SHALL run as a driver of the session through an adapter. The adapter SHALL open the port or device exclusively and close it afterwards in every case. It SHALL write all sent and received bytes to the diagnostic capture and report progress and activity to the session. It SHALL report protocol errors of the driver as protocol errors with a detail text.

#### Scenario: Protocol error
- **WHEN** a driver reports that the device sent an unexpected answer
- **THEN** the app shows the message for protocol errors, and the detail text names the answer

#### Scenario: Capture
- **WHEN** a read operation with a simulated device ends
- **THEN** the diagnostic capture contains all sent and received bytes

#### Scenario: Capture over Bluetooth
- **WHEN** a GNS 2000 is read
- **THEN** the capture contains the bytes sent and received over the RFCOMM channel

### Requirement: GPS week rollover correction when reading
The adapter of the drivers SHALL apply the GPS week rollover correction of the GPSLoggerKit spec `logger-kit` to every read result, with the time of reading as reference, for track points and waypoints. The correction SHALL always be active. A driver that splits or names tracks by time SHALL use the corrected times for that.

#### Scenario: Logger with week rollover
- **WHEN** on 13 November 2026 a simulated device returns a point with the time 2 November 2026 minus 1024 weeks
- **THEN** the point has the time 2 November 2026 in the result

#### Scenario: Current times stay
- **WHEN** a simulated device returns a point less than 512 weeks before the time of reading
- **THEN** its time is unchanged in the result

#### Scenario: Track names after the correction
- **WHEN** a GNS 2000 returns points whose times are 1024 weeks too early
- **THEN** the tracks carry the names of the corrected times, and no additional track boundary appears

### Requirement: Device hints
The device catalog SHALL be able to define hints per device with a condition: always or when a Bluetooth port is chosen. The window SHALL show the applicable hints below the port choice. A hint with a condition SHALL also appear in the error message of a failed read operation, for example after a timeout or an unexpected answer.

#### Scenario: M-241 over Bluetooth
- **WHEN** "Holux M-241" and a Bluetooth port are chosen
- **THEN** a hint advises to connect the logger via USB

#### Scenario: Failure over Bluetooth
- **WHEN** reading the M-241 over a Bluetooth port fails because the device does not answer or answers unexpectedly
- **THEN** the error message names the same hint

### Requirement: Missing driver
If a serial device is chosen and a USB device with the vendor ID of a known USB serial chip (Silicon Labs, Prolific, FTDI, WCH) is plugged in without a port, the window SHALL point to the probably missing driver and link the vendor's driver page.

#### Scenario: Driver missing
- **WHEN** a serial device is chosen and a USB device with the vendor ID of Prolific (0x067B) is plugged in, but has no port
- **THEN** a hint names the missing Prolific driver and links the driver page

#### Scenario: Driver present
- **WHEN** the USB device has a port
- **THEN** no hint on a missing driver appears
