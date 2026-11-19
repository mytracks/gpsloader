# serial-transport Specification

## Purpose
Byte-level communication with GPS loggers over serial ports (`/dev/cu.*`) as provided by USB serial adapters and paired Bluetooth devices. The communication has fixed time limits and can be cancelled at any time.

## Requirements

### Requirement: List ports
The system SHALL list all serial ports `/dev/cu.*` that currently exist. For USB devices it SHALL also provide vendor ID, product ID and product name where available.

#### Scenario: USB serial adapter connected
- **WHEN** a logger with a CP210x adapter is connected
- **THEN** the list contains the port (for example `/dev/cu.SLAB_USBtoUART`) with vendor and product ID

#### Scenario: Paired Bluetooth device
- **WHEN** a paired Bluetooth logger provides a port `/dev/cu.<name>`
- **THEN** the list contains this port without USB data

### Requirement: Detect port changes
The system SHALL report when serial ports appear or disappear, so that the UI can update the list without a restart.

#### Scenario: Device is plugged in
- **WHEN** a USB serial device is plugged in while the app runs
- **THEN** a new port is reported

### Requirement: Open and configure a port
The system SHALL be able to open a port exclusively with a given baud rate (at least 4800, 9600, 19200, 38400, 57600, 115200), 8 data bits, no parity, 1 stop bit, no flow control and in raw mode.

#### Scenario: Open with 115200 baud
- **WHEN** a driver requests an existing port with 115200 baud
- **THEN** the port is open with 115200 8N1 in raw mode

#### Scenario: Port does not exist
- **WHEN** a driver wants to open a port that does not exist
- **THEN** opening fails with the error "device not found"

#### Scenario: Port already open
- **WHEN** a port is open exclusively in another process
- **THEN** opening fails with the error "port busy"

### Requirement: Read with a time limit
The system SHALL offer reads with a time limit: a certain number of bytes or everything up to a terminator (for example `\r\n`). If the time limit expires without complete data, the read MUST end with "timeout".

#### Scenario: Read a line
- **WHEN** the device sends `$TEST,1,2\r\n` and a line up to `\r\n` is requested
- **THEN** the read returns the line without the terminator

#### Scenario: Data in pieces
- **WHEN** 4096 bytes are requested and the device sends them in several pieces
- **THEN** the read returns only after all 4096 bytes

#### Scenario: Device is silent
- **WHEN** no data arrives within the time limit
- **THEN** the read ends with "timeout"

### Requirement: Write
The system SHALL send byte sequences completely to the device. A write error MUST be reported as an error.

#### Scenario: Send a command
- **WHEN** a driver sends 16 bytes
- **THEN** all 16 bytes are passed to the port

### Requirement: Cancellation and release
The system MUST end a running read or write at once on cancellation. It SHALL release the port in every case: on success, on error and on cancellation.

#### Scenario: Cancel while reading
- **WHEN** a read waits for data and is cancelled
- **THEN** the read ends with "cancelled" and the port is closed

#### Scenario: Device is unplugged
- **WHEN** the device is removed during the communication
- **THEN** the running operation ends with an error and the port is released

### Requirement: Exchangeable transport
Drivers MUST communicate through a transport abstraction. So the same driver can be tested without hardware against a given or recorded device dialog.

#### Scenario: Driver against a mock transport
- **WHEN** a driver runs with a mock transport that returns a given answer to an expected command
- **THEN** the driver behaves as if a real device were connected

#### Scenario: Unexpected command in the mock
- **WHEN** a driver sends a command that the mock transport does not expect
- **THEN** the test fails with a message that names the expected and the actual command

### Requirement: Change the baud rate
An open port SHALL be able to switch its baud rate to any supported rate without being closed. An unsupported rate MUST be rejected with a protocol error.

#### Scenario: Switch after the negotiation
- **WHEN** a driver opens the port with 9600 baud and then switches to 115200 baud
- **THEN** all further reads and writes run with 115200 baud

### Requirement: Kind of port
For every serial port the system SHALL state whether it belongs to a USB device, to a paired Bluetooth device or to the system. System ports are `Bluetooth-Incoming-Port` and ports without a USB or Bluetooth device whose name contains `debug`.

#### Scenario: Paired Bluetooth device
- **WHEN** a paired Bluetooth logger provides the port `/dev/cu.HOLUX_M-241-SPPSlave`
- **THEN** the port is marked as a Bluetooth port

#### Scenario: System port
- **WHEN** the ports `/dev/cu.Bluetooth-Incoming-Port` and `/dev/cu.debug-console` exist
- **THEN** both are marked as system ports

### Requirement: List USB devices
The system SHALL list all connected USB devices with vendor ID, product ID and, where available, vendor and product name. Serial numbers MUST NOT be read.

#### Scenario: Adapter without driver
- **WHEN** a USB serial adapter is plugged in for which no driver is loaded
- **THEN** it appears in the list of USB devices, although it has no port
