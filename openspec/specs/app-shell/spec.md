# app-shell Specification

## Purpose
The app frame of myTracks Loader: start on all supported Macs, main window, license notices for included third-party components and ported templates, name, icon and localization.

## Requirements

### Requirement: Supported systems
The app MUST start on macOS 12 and later, natively on both Apple silicon and Intel Macs, without Rosetta for the app itself.

#### Scenario: Start on Apple silicon
- **WHEN** the app is started on an Apple silicon Mac with macOS 12 or later
- **THEN** the app process runs natively (arm64) and the main window appears

#### Scenario: Start on Intel
- **WHEN** the app is started on an Intel Mac with macOS 12 or later
- **THEN** the app process runs natively (x86_64) and the main window appears

### Requirement: License notices
The app SHALL state in the About window that it is licensed under the GNU GPL version 3 or later and where its source code is available. It SHALL also name GPSLoggerKit under the MIT License and the authors of the templates of ported formats and drivers, each with the source of their code. It MUST NOT name gpsbabel and Qt as bundled programs. The texts of the GPL version 3 and of the MIT License MUST be included in the app bundle.

#### Scenario: Open the About window
- **WHEN** the user chooses "About myTracks Loader"
- **THEN** the window shows the app version, the copyright, the app's license with a link to its source code and the license notice for GPSLoggerKit
- **AND** it mentions neither gpsbabel 1.7.0 nor Qt as bundled programs

#### Scenario: Ported formats
- **WHEN** GPSLoggerKitGPL contains formats or drivers based on templates
- **THEN** the About window names the authors of these templates or refers to a bundled list that names them

#### Scenario: License texts in the bundle
- **WHEN** the shipped app bundle is examined
- **THEN** it contains the complete texts of the GPL version 3 and of the MIT License of GPSLoggerKit
- **AND** it contains no `Contents/Helpers` and no Qt framework

### Requirement: Localization
All visible texts of the app MUST be available in German and English. The language SHALL follow the system setting, with English as the fallback.

#### Scenario: German system
- **WHEN** the preferred system language is German
- **THEN** all texts of the app appear in German

#### Scenario: Unsupported language
- **WHEN** the preferred system language is neither German nor English
- **THEN** all texts of the app appear in English

### Requirement: Sections of the main window
The main window SHALL show a toggle with the sections "Convert Files" and "Read Device" in the toolbar and below it only the chosen section. The "View" menu SHALL offer both sections with ⌘1 and ⌘2. The app SHALL show the last chosen section again at the next start; at the first start "Read Device" SHALL be chosen.

#### Scenario: First start
- **WHEN** the app starts for the first time
- **THEN** the main window shows the section "Read Device", and this section is chosen in the toggle

#### Scenario: Remember the section
- **WHEN** the user chooses "Convert Files" and restarts the app
- **THEN** the main window shows the section "Convert Files"

#### Scenario: Keyboard shortcut
- **WHEN** the user presses ⌘2 in the section "Convert Files"
- **THEN** the main window shows the section "Read Device"

### Requirement: Name of the app
For users the app MUST be called "myTracks Loader": in the Finder, in the Dock, in the app menu and its commands, in window titles, in the About window, in all localized texts and in the explanation of system dialogs. The app bundle MUST be called `myTracks Loader.app`. The bundle ID MUST stay `info.stichling.gpsloader`, so that stored settings are kept.

#### Scenario: App menu
- **WHEN** the user opens the app menu
- **THEN** it is called "myTracks Loader" and contains "About myTracks Loader" and "Quit myTracks Loader" (German "Über myTracks Loader" and "myTracks Loader beenden")

#### Scenario: Old name not visible
- **WHEN** all localized texts of the app and its Info.plist are searched in German and English
- **THEN** "gpsloader" appears in no visible text, only in identifiers such as the bundle ID and the source code address

#### Scenario: Settings are kept
- **WHEN** a version with the new name starts on a Mac where an earlier version stored device, port and section
- **THEN** the app shows the same choice as before

### Requirement: App icon
The app SHALL have an icon in the style of myTracks Neo: a vertical gradient from `#1A46DE` at the top to `#9F199C` at the bottom with a white satellite in line art on it. The icon MUST be available in all sizes that macOS 12 and later use in the Finder, in the Dock and in the About window. It MUST be generated reproducibly from a versioned source.

#### Scenario: Icon in the Dock
- **WHEN** the app is running
- **THEN** the Dock shows the satellite icon and not the generic app icon

#### Scenario: About window
- **WHEN** the user opens the About window
- **THEN** it shows the app icon

#### Scenario: Reproducible
- **WHEN** the icon is generated again from its source
- **THEN** the generated images match those in the repository
