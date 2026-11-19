# support-package Specification

## Purpose
Bundles everything the developer needs to analyze a problem of a user into a ZIP that the user sends personally: system and app information, app log, ports, devices and diagnostic captures.

## Requirements

### Requirement: Create a support package
The app SHALL offer the command "Create Support Package…" in the "Help" menu. The error message of a failed read or erase operation SHALL offer the same command as a button. The command SHALL show the contents of the package with check boxes, all chosen by default, and then open a save dialog with the name `myTracks-Loader-Support-<date>-<time>.zip`.

#### Scenario: After an error
- **WHEN** reading fails with a timeout and the user chooses "Create Support Package…" in the error message
- **THEN** the app shows the list of contents, and after saving there is a ZIP with the capture of this operation

#### Scenario: Content deselected
- **WHEN** the user deselects the diagnostic captures
- **THEN** the ZIP contains no captures

#### Scenario: Suggested name
- **WHEN** the user creates a support package on 19 November 2026 at 14:05
- **THEN** the save dialog suggests `myTracks-Loader-Support-20261119-1405.zip`

### Requirement: Content of the support package
The ZIP SHALL contain an overview file with the list of parts and, depending on the choice:
- system and app: app version and build, macOS version, Mac model, architecture, Rosetta, languages, time zone
- the app log and the settings of the app
- serial ports and USB devices with vendor ID, product ID and names, without serial numbers
- paired Bluetooth devices
- the stored diagnostic captures
- the crash reports of the app, also those under the old name "gpsloader"

#### Scenario: Complete package
- **WHEN** the user creates a package with all contents
- **THEN** the ZIP contains the overview file, the system report, the log, the settings, the list of ports and USB devices and all stored captures

#### Scenario: No serial numbers
- **WHEN** a USB device with a serial number is connected
- **THEN** the serial number does not appear in the package

### Requirement: Privacy in the support package
The list of contents MUST point out that diagnostic captures contain position data. The package MUST only be saved locally; the app MUST neither send nor upload it. The list of Bluetooth devices SHALL only be offered when the app already has the Bluetooth permission; creating the package MUST NOT trigger a permission dialog.

#### Scenario: Without Bluetooth permission
- **WHEN** the app has no Bluetooth permission yet and the user creates a package
- **THEN** no permission dialog appears, and the list of contents names the Bluetooth devices as not available

### Requirement: App log
The app SHALL write a log in `~/Library/Logs/myTracks Loader/`: start with app and macOS version, ports appearing and disappearing, choice of device and port, start and result of every operation and conversion, errors with details. Positions and file names MUST NOT be in the log. It SHALL rotate and use at most 5 MB in total. At start the app SHALL move folders with the old name "gpsloader" to the new name if the new one does not exist yet.

#### Scenario: Failed operation
- **WHEN** a read operation ends with a protocol error
- **THEN** the log contains device, port, result and detail text of this operation with a timestamp

#### Scenario: Rotation
- **WHEN** the log file exceeds the size limit
- **THEN** a new file starts, and the oldest files are deleted so that all together use at most 5 MB

#### Scenario: Folder with the old name
- **WHEN** the app starts and `~/Library/Logs/gpsloader/` exists, but not `~/Library/Logs/myTracks Loader/`
- **THEN** the previous log is in `~/Library/Logs/myTracks Loader/` afterwards, and the app continues writing there

#### Scenario: Both folders exist
- **WHEN** the app starts and both folders exist
- **THEN** the app leaves the old folder unchanged and writes to the new one
