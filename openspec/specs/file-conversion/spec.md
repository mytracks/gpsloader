# file-conversion Specification

## Purpose
The file mode of myTracks Loader: choosing files from a memory card or USB storage whose format GPSLoggerKit or GPSLoggerKitGPL reads natively and saving them as a GPX file, without gpsbabel and without Rosetta.

## Requirements

### Requirement: Choose files
The app SHALL offer the command "Convert Files…" in the "File" menu (⌘O) and as a button in the section "Convert Files", together with a drop zone there. The command SHALL switch to this section and open a file dialog for one or more files. The app SHALL accept files dragged onto the main window in every section, switch to "Convert Files" and convert them.

#### Scenario: Choice through the menu
- **WHEN** the user chooses "File > Convert Files…" and selects two NMEA files
- **THEN** the conversion of these two files starts

#### Scenario: Drag and drop
- **WHEN** the user drags an IGC file from the Finder onto the main window
- **THEN** the conversion of this file starts

#### Scenario: Folder dragged
- **WHEN** the user drags a folder onto the main window
- **THEN** the app does not accept it

#### Scenario: Drag and drop in the device section
- **WHEN** the section "Read Device" is shown and the user drags an NMEA file onto the window
- **THEN** the window shows the section "Convert Files", and the conversion starts

### Requirement: Supported formats
The app SHALL convert all formats of its catalog. The catalog SHALL consist of the formats of GPSLoggerKit and of GPSLoggerKitGPL. The format of each file SHALL be determined by format detection on this catalog. If a format is added to one of the two packages, it SHALL be available without a change to the app. The file dialog SHALL allow all files to be chosen, because the extension is only a hint.

#### Scenario: NMEA with extension .LOG
- **WHEN** the user chooses the file `GPS_20261102.LOG` of a Canon EOS
- **THEN** it is detected as NMEA 0183 and converted

#### Scenario: New format in the catalog
- **WHEN** GPSLoggerKit or GPSLoggerKitGPL adds another format to its catalog
- **THEN** the app converts files of this format without a change to its code

#### Scenario: Format from the GPL package
- **WHEN** the conversion is checked with a catalog that additionally contains a test format, and a file of this format is chosen
- **THEN** it is read with the test format and included in the GPX file

### Requirement: Unrecognized files
If the format of a file is not recognized, the app SHALL name this file and offer to continue without it or to cancel. If none of the files is recognized, the app SHALL only report that the format is not supported and convert nothing.

#### Scenario: One of three files unknown
- **WHEN** the user chooses two NMEA files and a JPEG image
- **THEN** the app names the image as not supported and offers "Continue Without This File" and "Cancel"

#### Scenario: Only unknown files
- **WHEN** the user chooses only a PDF file
- **THEN** the app reports that the format is not supported and shows no save dialog

### Requirement: Merge several files
Several files SHALL result in a single GPX file. Files of the same format SHALL be read together in the chosen order, so that the rules of the format for several files apply. The results of different formats SHALL be joined in the order of their first appearance: first all tracks, then all waypoints.

#### Scenario: Two NMEA files
- **WHEN** the user converts two NMEA files with 100 points each
- **THEN** the GPX file contains one track with two segments and 200 points

#### Scenario: Mixed formats
- **WHEN** the user converts a GPX file with one track and an IGC file
- **THEN** the GPX file contains two tracks, first the one from the GPX file, then the one from the IGC file

### Requirement: Post-processing
When converting, the app SHALL correct the GPS week rollover. If the merged result contains no tracks but waypoints, the app SHALL turn the waypoints into a track.

#### Scenario: Only waypoints
- **WHEN** a GPX file contains only 12 waypoints
- **THEN** the generated GPX file contains one track with these 12 points

#### Scenario: Old logger with week rollover
- **WHEN** an NMEA file contains times more than 512 weeks before today
- **THEN** these times are shifted by 1024 weeks in the GPX file

### Requirement: Progress and cancellation
During the conversion the app SHALL show a progress window with "Cancel" and keep the main window usable. A cancellation SHALL end the conversion within one second, without a file and without an error message. While a conversion runs, the app SHALL not start a second one.

#### Scenario: Cancel a large file
- **WHEN** the user chooses "Cancel" while a 50 MB NMEA file is converted
- **THEN** the progress window closes within one second, and neither a save dialog nor an error message appears

#### Scenario: Second conversion
- **WHEN** a conversion runs and the user drags more files onto the window
- **THEN** the app does not accept them, and the menu command is disabled

### Requirement: Save
After successful reading the app SHALL show a save dialog and write the result as GPX 1.1 to the chosen place (see `gpx-export`). It suggests the name of the first converted file with the extension `.gpx` and, if possible, its folder.

#### Scenario: Suggest a name
- **WHEN** the user converts `flight1.igc` and `flight2.igc`
- **THEN** the save dialog suggests the name `flight1.gpx`

#### Scenario: Saving cancelled
- **WHEN** the user cancels the save dialog
- **THEN** no file is written and no message is shown

### Requirement: Errors and warnings
If a file cannot be read or contains no usable data, the app SHALL show the localized message of the package with the file name and, if present, the technical detail, and save nothing. If the import produced warnings, the app SHALL show them summarized after saving, one line per warning.

#### Scenario: Broken GPX file
- **WHEN** a GPX file is not well-formed in line 12
- **THEN** the app reports that the file is not well-formed, names file and line and shows no save dialog

#### Scenario: Discarded sentences
- **WHEN** an NMEA file contains three sentences with a wrong checksum
- **THEN** the GPX file is written, and afterwards the app reports that three records with a wrong checksum were skipped in this file

#### Scenario: No positions
- **WHEN** an NMEA file contains only sentences without a valid fix
- **THEN** the app reports that the file contains no usable data
