# diagnostic-capture Specification

## Purpose
Records the complete communication with devices. Users can report problems with devices that the developer does not have. Captures also serve as repeatable test fixtures.

## Requirements

### Requirement: Human- and machine-readable format
The format MUST be line-based, text-based and versioned. Bytes SHALL appear as hexadecimal digits and printable ASCII characters additionally as text, so that people can read the file and programs can process it.

#### Scenario: File in a text editor
- **WHEN** a capture of an NMEA-like dialog is opened in a text editor
- **THEN** the sent and received lines are recognizable as text

### Requirement: Replay in tests
A capture of a serial dialog MUST be replayable as a mock transport. A driver then gets the recorded answers to the bytes it sends. If the driver deviates from the recorded dialog, the replay MUST report that with position and content.

#### Scenario: Replay of a successful read
- **WHEN** a driver runs against the replay of a successful capture
- **THEN** it returns the same result as in the recorded operation

#### Scenario: Deviation
- **WHEN** the driver sends other bytes at position 5 than recorded
- **THEN** the replay fails with the expected and actual bytes at position 5

### Requirement: Limited storage
Captures MUST be stored only locally. The app SHALL keep only the captures of the last 10 operations and delete older ones automatically.

#### Scenario: Eleventh operation
- **WHEN** the eleventh operation is recorded
- **THEN** the oldest capture is deleted

### Requirement: Content of the capture
A capture MUST contain:
- header data: app version, macOS version, architecture, whether under Rosetta, driver, port and parameters
- all sent and received bytes in their actual order, each with a timestamp in milliseconds
- events such as open, close, timeout, cancellation and error

#### Scenario: Serial dialog
- **WHEN** a driver sends 16 bytes and receives 3 bytes
- **THEN** the capture contains an entry "sent" with the 16 bytes and after it an entry "received" with the 3 bytes, each with a timestamp

#### Scenario: App under Rosetta
- **WHEN** the user started the app under Rosetta and records an operation
- **THEN** the header data notes that the app runs under Rosetta

### Requirement: Capture always on
The app SHALL record every read and erase operation. There SHALL be no switch to turn it off. Captures MUST stay local until the user includes them in a support package.

#### Scenario: First start
- **WHEN** the app is started for the first time and the user reads a device
- **THEN** a capture of this operation exists afterwards

#### Scenario: Failed operation
- **WHEN** an operation ends with an error
- **THEN** its capture is stored just like that of a successful operation
