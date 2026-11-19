# bluetooth-transport Specification

## Purpose
Connects myTracks Loader through IOBluetooth to a paired Bluetooth device by opening the RFCOMM channel of a named SDP service. This applies to loggers that do not work through `/dev/cu.*`, such as the GNS 2000.

## Requirements

### Requirement: Find device and service
The transport SHALL look for the first paired Bluetooth device with one of the given names. It SHALL close an existing connection and open it again. Then it SHALL look for the service with the given name through an SDP query and open its RFCOMM channel. If the device, the service or the channel is missing, opening MUST end with the error "device not found" and a hint.

#### Scenario: Device not paired
- **WHEN** no paired device is called "GNS 2000" or "GNS 2000 plus"
- **THEN** the operation ends with "device not found" and the hint to pair the device in System Settings

#### Scenario: Service missing
- **WHEN** the device reports no service "GNS GPS"
- **THEN** the operation ends with "device not found", and the detail text names the service looked for

### Requirement: Time limits when connecting
Connecting and the SDP query together SHALL take at most 20 seconds, otherwise the operation MUST end with a timeout. A cancellation by the user SHALL end the wait at once and close the connection.

#### Scenario: Device switched off
- **WHEN** the paired device is switched off
- **THEN** the operation ends with a timeout after 20 seconds at the latest

### Requirement: Transfer data
The transport SHALL fulfil the interface `ByteTransport`: writing in chunks up to the MTU of the channel and reading a number of bytes or up to a terminator, each with a silence timeout. It SHALL buffer received data until it is read. If the device closes the channel, a waiting read MUST end with an error.

#### Scenario: Lines in several packets
- **WHEN** a line arrives in two RFCOMM packets
- **THEN** reading up to CR LF returns the whole line

#### Scenario: Device disconnects
- **WHEN** the device closes the channel while reading
- **THEN** reading ends with an error instead of a timeout

### Requirement: Close
After the operation the transport SHALL close the RFCOMM channel and the connection to the device, also after errors and cancellation. Closing several times MUST be harmless.

#### Scenario: Cancel while reading
- **WHEN** the user cancels while reading
- **THEN** channel and connection are closed afterwards

### Requirement: Bluetooth permission
The app SHALL bring an explanation for Bluetooth access (de/en) that macOS shows at the first use. If the user denies access, the operation MUST end with "device not found" and the hint to the privacy settings.

#### Scenario: Access denied
- **WHEN** the user has denied Bluetooth access for myTracks Loader
- **THEN** the error message names the setting "Privacy & Security > Bluetooth"
