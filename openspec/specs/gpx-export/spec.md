# gpx-export Specification

## Purpose
Creates standard-compliant GPX 1.1 files from the data read (tracks, segments, waypoints) that myTracks and other programs can import without adjustments.

## Requirements

### Requirement: GPX 1.1 conformance
Generated files MUST be valid GPX 1.1 according to the schema `http://www.topografix.com/GPX/1/1` in UTF-8. The `creator` attribute SHALL contain "myTracks Loader" and the app version, for example "myTracks Loader 0.1.0". The file SHALL not contain extensions, in particular not those of myTracks.

#### Scenario: Validation against the schema
- **WHEN** a generated file is checked against the GPX 1.1 XSD
- **THEN** it is valid

#### Scenario: No extensions
- **WHEN** a file is generated
- **THEN** it contains no `extensions` element

#### Scenario: Creator
- **WHEN** the app in version 0.1.0 generates a file
- **THEN** its `creator` attribute is "myTracks Loader 0.1.0"

### Requirement: Content
Each track SHALL be written as `trk` with a name and one or more `trkseg`. Each point appears as `trkpt` with latitude and longitude and, if present, elevation (`ele`) and time (`time`). Waypoints SHALL be written as `wpt`. Existing quality data SHALL appear in the order of the GPX 1.1 schema as `fix`, `sat`, `hdop`, `vdop` and `pdop`. Speed and course SHALL not be written.

#### Scenario: Track with segments
- **WHEN** a track with two segments of 3 points each is exported
- **THEN** the file contains one `trk` with two `trkseg` of three `trkpt` each

#### Scenario: Point without elevation
- **WHEN** a point has no elevation
- **THEN** its `trkpt` contains no `ele` element

#### Scenario: Waypoint
- **WHEN** a waypoint named "WPT" is exported
- **THEN** the file contains a `wpt` with `name` "WPT"

#### Scenario: Point with quality data
- **WHEN** a point has a 3D fix, 8 satellites and HDOP 0.9
- **THEN** its `trkpt` contains `<fix>3d</fix>`, `<sat>8</sat>` and `<hdop>0.9</hdop>` in this order, and the file stays valid according to the GPX 1.1 XSD

#### Scenario: Speed is not written
- **WHEN** a point has a speed
- **THEN** the file contains neither a `speed` element nor an extension for it

### Requirement: Times in UTC
Times MUST be written as ISO 8601 in UTC with the suffix `Z`. Fractions of seconds SHALL only appear when they are not zero.

#### Scenario: Whole seconds
- **WHEN** a point has the time 2 November 2026, 14:30:05 UTC
- **THEN** `time` is `2026-11-02T14:30:05Z`

#### Scenario: Milliseconds
- **WHEN** a point has the time 14:30:05.250 UTC
- **THEN** `time` is `2026-11-02T14:30:05.250Z`

### Requirement: Locale-independent numbers
Coordinates and elevations MUST be written with a point as decimal separator and without thousands separators, independent of the system language. Coordinates SHALL have up to 7 decimal places, without trailing zeros.

#### Scenario: German locale
- **WHEN** the system is set to German and a point has the latitude 51.7411580
- **THEN** the attribute is `lat="51.741158"`

### Requirement: Special characters in texts
Names and descriptions MUST be escaped correctly for XML.

#### Scenario: Name with special characters
- **WHEN** a track is called "Hill & Dale <1>"
- **THEN** the file is well-formed and the name is read back unchanged as "Hill & Dale <1>"

### Requirement: Deterministic output
The same input data MUST result in byte-identical files, except for the creation time in `metadata/time`.

#### Scenario: Export twice
- **WHEN** the same data is exported twice with a fixed creation time
- **THEN** both files are byte-identical

### Requirement: Safe writing
The file MUST be written atomically. If writing fails, no incomplete file SHALL remain at the destination, and an existing file with the same name MUST stay unchanged.

#### Scenario: Destination not writable
- **WHEN** the destination folder is read-only
- **THEN** a write error is reported, and no file appears at the destination
