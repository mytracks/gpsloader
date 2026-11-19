# logger-session Specification

## Purpose
The uniform flow of a read or erase operation on a GPS logger, independent of the specific driver: progress, cancellation, time limits, error messages, confirmation before erasing and saving the result as GPX.

## Requirements

### Requirement: Uniform driver contract
Every driver MUST be used through the same contract. It covers reading, optionally erasing, whether erasing is supported and whether it is considered experimental, and progress reports. The session SHALL work with drivers only through this contract.

#### Scenario: Driver without erasing
- **WHEN** a driver states that it does not support erasing
- **THEN** the session offers no erase action for this device

#### Scenario: Experimental erasing
- **WHEN** a driver considers erasing experimental
- **THEN** the session points out explicitly before the confirmation that erasing was not tested with a real device

### Requirement: Progress
During an operation the session SHALL report the progress: determinate with read and expected units as soon as the driver knows the total, otherwise indeterminate.

#### Scenario: Determinate progress
- **WHEN** a driver reports that 250 of 1000 points have been read
- **THEN** the session shows a progress of 25 %

#### Scenario: Indeterminate progress
- **WHEN** a driver does not know the total
- **THEN** the session shows an indeterminate progress with the description of the current step

### Requirement: Time limit without an answer
If an operation receives no data from the device for longer than the time set by the driver, the session MUST end it with the error "timeout" instead of waiting without limit.

#### Scenario: Device does not answer
- **WHEN** a device sends no data after the connection was opened
- **THEN** the operation ends after the time limit with the error "timeout" and a hint to check the connection and the device choice

### Requirement: Save the result
After a successful read the session SHALL save the result as a GPX file at a place chosen by the user. The suggested file name MUST contain the device name and the date and time of reading.

#### Scenario: Successful read
- **WHEN** a driver returns a track with 120 points
- **THEN** the session suggests a file name like "Device name 2026-11-02 14-30.gpx"
- **AND** after confirmation writes a GPX file with these 120 points

#### Scenario: No data on the device
- **WHEN** a driver reads successfully but returns no points and no waypoints
- **THEN** the session reports that the logger contains no data and writes no file

### Requirement: Confirmation before erasing
The session MUST start an erase operation only after an explicit confirmation by the user. The confirmation dialog MUST point out that erased data cannot be restored.

#### Scenario: Erasing declined
- **WHEN** the user cancels the confirmation dialog for erasing
- **THEN** no command is sent to the device

#### Scenario: Erasing confirmed
- **WHEN** the user confirms erasing and the driver erases successfully
- **THEN** the session reports that the data has been erased

### Requirement: Only one operation at a time
The app MUST prevent two operations from using the same device or the same port at the same time.

#### Scenario: Second start during a running operation
- **WHEN** an operation runs and the user wants to start another operation for the same port
- **THEN** the second operation is not started and the user gets a hint

### Requirement: Cancelling an operation
The user MUST be able to cancel every running operation. After a cancellation the session SHALL release all device connections within 5 seconds. It SHALL discard partial results.

#### Scenario: Cancel while reading
- **WHEN** the user chooses "Cancel" while reading
- **THEN** the operation ends with the status "cancelled"
- **AND** no GPX file is written
- **AND** the serial port is free again afterwards

### Requirement: Error messages of the session
The session SHALL report errors as understandable, localized messages with the kind of error and the technical detail. The kinds of error are: device not found, port busy, timeout, protocol error, write error, cancelled.

#### Scenario: Port busy
- **WHEN** the chosen serial port is already open in another program
- **THEN** the session reports "port busy" with the port name

#### Scenario: Protocol error
- **WHEN** a driver reports an unexpected answer of the device
- **THEN** the session reports "protocol error" and shows the driver's message as detail
