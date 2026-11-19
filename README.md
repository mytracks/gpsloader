# myTracks Loader

Standalone macOS app that reads GPS loggers and converts logger files to GPX.
myTracks Loader replaces the logger functions of myTracks. The repository, the Xcode target and the bundle ID
(`info.stichling.gpsloader`) keep the name `gpsloader`. The app is distributed by download
([GitHub releases](https://github.com/mytracks/gpsloader/releases)), not through the App Store.

Planning and requirements: `openspec/` (spec-driven with OpenSpec), background: `docs/legacy-analysis.md`.

## Requirements

- macOS with **Xcode 27** (Swift 6.4, macOS 27 SDK); the deployment target of the app is macOS 12.
- **XcodeGen** (`brew install xcodegen`). The Xcode project is generated from `project.yml` and not checked in.
- For signing: the certificates "Apple Development" and "Developer ID Application" of the team `4TNB35NY7G`.

## Build and run

```sh
xcodegen generate
xcodebuild -project gpsloader.xcodeproj -scheme gpsloader -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/myTracks Loader.app"
```

Alternatively open the project `gpsloader.xcodeproj` in Xcode after `xcodegen generate`.

## Usage

The main window has two sections, switched in the toolbar or through "View" (⌘1 "Convert Files", ⌘2 "Read Device").
The app remembers the last chosen section; at the first start "Read Device" is chosen.

- **File mode:** "File > Convert Files…" (⌘O), "Choose Files…" or a click on the drop zone in the section
  "Convert Files", or drag files onto the main window (in both sections; the window then switches to "Convert
  Files"). The format is detected from the content. Several files result in one GPX file.
  - `GPSLoggerKit`: NMEA 0183, GPX, IGC, Garmin FIT, TCX, Suunto SML, KML/KMZ, Columbus V-900 and iBlue 747/757 (CSV).
  - `GPSLoggerKitGPL`: memory images of SkyTraq, MTK and Holux loggers, Wintec TES/BIN/TK1, Locosys SBP/SBN,
    Medion GoPal tracks, Magellan SD files and Alan Map500 track logs.
- **Direct mode:** choose device and port in the section "Read Device", then "Read" or "Erase Memory…".
  Ports appear with readable names ("USB: … (Prolific PL2303)", "Bluetooth: …"); a port whose name fits the device is
  at the top and preselected, system ports are hidden. Below the choice there are hints for the device (for example
  M-241 not over Bluetooth, pair the GNS 2000 first) and, when a USB serial chip without a port is plugged in, a hint
  on the missing driver with a link to the vendor.
  Native drivers: `GPSLoggerKitGPL` for SkyTraq, MTK/Holux, Wintec, Navilink, Magellan, XAiOX iTrackU and i-GotU
  (GT-800 serial, other models over USB HID; erasing experimental), `GPSLoggerKit` for the GNS 2000 over Bluetooth.
- **Support:** "Help > Create Support Package…" or the button in the error message of an operation saves a ZIP with
  system and app information, app log, settings, ports and USB devices, paired Bluetooth devices (only with an
  existing Bluetooth permission), the diagnostic captures of the last 10 operations and crash reports. Every part can
  be deselected; captures contain position data. The capture is always on; the app log is in
  `~/Library/Logs/myTracks Loader/` (at most 5 MB).

## Tests

The connection of the drivers, transports, session and support package live in the local Swift package
`Packages/GPSLoaderKit` and are testable without hardware:

```sh
swift test --package-path Packages/GPSLoaderKit
```

The formats and device protocols are tested in their own repositories (see "Packages").

Check the localization (after a debug build, see above):

```sh
swift Scripts/check-localizations.swift
```

### Debug helpers

Debug builds contain a demo driver and launch arguments to check UI states without hardware
(see `App/DebugAutomation.swift`), for example:

```sh
"build/DerivedData/Build/Products/Debug/myTracks Loader.app/Contents/MacOS/myTracks Loader" \
    -DebugDemo success -AppleLanguages '(de)'
```

File conversion without dialogs (writes to `-DebugSaveDirectory`, screenshots to `-DebugSnapshotDirectory`):

```sh
"build/DerivedData/Build/Products/Debug/myTracks Loader.app/Contents/MacOS/myTracks Loader" \
    -DebugConvert /path/a.nmea,/path/b.igc -DebugSaveDirectory /tmp/out -DebugQuitAfter 5
```

Preset the section (`-DebugSection files|device`), send a keyboard shortcut through the menu (`-DebugKeyEquivalent 2`)
and choose the times of the screenshots (`-DebugSnapshotTimes 1.5,3`). Screenshots of a directly started binary show
the generic app icon; start with `open -n "…/myTracks Loader.app" --args …` to see the real one.

Write a support package without dialogs (`-DebugShowSupportPackage <s>` opens the dialog instead,
`-DebugNoBluetoothPermission YES` shows it as without Bluetooth permission):

```sh
"build/DerivedData/Build/Products/Debug/myTracks Loader.app/Contents/MacOS/myTracks Loader" \
    -DebugSupportPackagePath /tmp/support.zip -DebugQuitAfter 4
```

Check port names and hints without hardware (invented ports and USB devices, see `DebugPorts` in
`App/DevicePanel.swift`):

```sh
"build/DerivedData/Build/Products/Debug/myTracks Loader.app/Contents/MacOS/myTracks Loader" \
    -DebugPorts "bt:/dev/cu.HOLUX_M-241-SPPSlave,usb:/dev/cu.usbserial-1410:067B:2303:USB-Serial Controller" \
    -DebugUSBDevices "067B:2303" -DebugSelectDevice m241.holux-m-241 -DebugSnapshotDirectory /tmp/snap -DebugQuitAfter 3
```

Read a device from the catalog, for example against a simulated device on a pseudo terminal:

```sh
"build/DerivedData/Build/Products/Debug/myTracks Loader.app/Contents/MacOS/myTracks Loader" \
    -DebugReadDevice skytraq.venus -DebugPort /dev/ttys012 -DebugSaveDirectory /tmp/out -DebugQuitAfter 10
```

## Release

```sh
Scripts/release.sh --publish            # also tag <version> and GitHub release with ZIP, checksum and docs/releases/<version>.md
Scripts/release.sh --publish --dry-run --skip-notarize --allow-unpublished   # test the script without publishing anything
Scripts/release.sh                      # archive, Developer ID export, notarization, stapling -> build/release/myTracks-Loader-<version>.zip
Scripts/release.sh --skip-notarize      # only a signed ZIP for own tests, not for users
Scripts/release.sh --allow-unpublished  # notarize without checking that the commit is clean and pushed
Scripts/verify-bundle.sh <app>          # check signatures, hardened runtime, architectures, licenses and icon
```

Before the long build `release.sh` checks that the commit is clean and pushed to `origin` (GPL: the source of every
version is public), that signing in for notarization works and that the Developer ID certificate exists. The ZIP for
users contains the app with the stapled notarization ticket; next to it is `myTracks-Loader-<version>.zip.sha256`.
If Apple rejects the submission, its log is in `build/release/notarization-log.json`.

Like myTracks Neo, notarization signs in with the App Store Connect API key
`~/.appstoreconnect/private_keys/app-manager_<key ID>.p8`. The issuer ID comes from `NOTARY_ISSUER_ID`, else from
`~/.appstoreconnect/issuer_id`, else it is the team's. Without a key the script uses a keychain profile that is
created once:

```sh
xcrun notarytool store-credentials gpsloader-notary --apple-id <Apple ID> --team-id 4TNB35NY7G
```

## Packages

Since 2026-11-19 formats and device protocols live in repositories of their own. The app uses them in
`Packages/GPSLoaderKit/Package.swift` by URL, with the versions from `Packages/GPSLoaderKit/Package.resolved`:

| Package | License | Repository |
|---|---|---|
| GPSLoggerKit | MIT, macOS 12+ and iOS/iPadOS 27+ | https://github.com/mytracks/GPSLoggerKit |
| GPSLoggerKitGPL | GPL-3.0-or-later, macOS only | https://github.com/mytracks/GPSLoggerKitGPL |

Flow for a feature that concerns a package and the app:
1. Change and release in the package repository (`Scripts/release.sh <version>` there).
2. Change here: raise the version in `Package.swift`, resolve (`swift package update` in `Packages/GPSLoaderKit`) and
   add catalog, transport or UI.

Develop against a local package checkout; the repositories lie next to each other:

```sh
cd Packages/GPSLoaderKit
swift package edit GPSLoggerKit --path ../../../GPSLoggerKit       # local checkout instead of the URL
swift package unedit GPSLoggerKit                                  # back to the version from Package.resolved
```

In Xcode it is enough to drag the package folder into the project; Xcode then uses it instead of the URL.

## App icon

The icon (`App/AppIcon.icon`, Icon Composer) is generated from a fixed geometry: the gradient of myTracks Neo and a
satellite. Xcode also renders the images for macOS 12–15 from it.

```sh
swift Scripts/make-app-icon.swift generate --variant 3     # generate App/AppIcon.icon again (chosen variant)
swift Scripts/make-app-icon.swift preview /tmp/icons       # preview of all variants (full-bleed and macOS shape)
```

## Structure

| Place | Content |
|---|---|
| `App/` | AppKit app (UI, localization `Localizable.xcstrings`) |
| `Packages/GPSLoaderKit/` | `LoggerCore` (driver contract, session), `SerialTransport`, `GPXExport` (file name, writing), `DiagnosticCapture`, `FileConversion` (file mode: detection, merging), `DeviceDrivers` (device catalog, connection of the drivers), `HIDTransport` (USB HID), `BluetoothTransport` (Bluetooth RFCOMM, GNS 2000), `SupportPackage` (app log, support package), `TestSupport` |
| `Vendor/Licenses/` | License texts for the app bundle: GPL-3.0 (copy of `LICENSE`) and the MIT License of GPSLoggerKit |
| `docs/releases/` | Release notes per version (text of the GitHub release) |
| `Scripts/` | Release, bundle check, localization check, app icon (`make-app-icon.swift`) |

## Without gpsbabel

myTracks Loader reads all formats and devices with native Swift drivers (GPSLoggerKit and GPSLoggerKitGPL). Until
2026-11-13 gpsbabel 1.7.0 with Qt was bundled; since the change `remove-gpsbabel` the app contains no helper programs
and does not need Rosetta on Apple silicon either. For black-box cross-checks of ports the gpsbabel 1.7.0 binary from
the myTracks history (commit `e0d1f18`) is copied to a temporary folder, never into the repository.

The 45 formats of map and navigation programs that myTracks offered through gpsbabel (for example OziExplorer,
Garmin MapSource, CompeGPS) are no longer supported; the list is in the proposal of `remove-gpsbabel`.

## License

- myTracks Loader (app, `GPSLoaderKit`) and `GPSLoggerKitGPL` are licensed under the **GNU GPL version 3 or later**
  (GPL-3.0-or-later, see `LICENSE`). Whoever distributes the app must offer the complete source code.
- `GPSLoggerKit` is licensed under the **MIT License** (file `LICENSE` in its repository) and contains no code derived
  from GPL sources.
