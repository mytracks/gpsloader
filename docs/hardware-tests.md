# Open hardware and user tests

As of 2026-11-13. The changes are archived, but these tests are still open. The developer did not have the loggers at hand at that time. Every entry names the change (below `openspec/changes/archive/`) and the task it comes from. Tick it here after a test and record deviations as a new change or bug report.

## Comparison with gpsbabel

- **Where gpsbabel comes from:** the app no longer contains gpsbabel (change `remove-gpsbabel`). The comparisons use the gpsbabel 1.7.0 binary of the old app:
  - from the myTracks history (`input/mytracks4mac`, commit `e0d1f18`) or
  - from `Import/Apps/GPSBabelFE170.app`, with `QtCoreGpsBabel.framework`.

  It is copied to a temporary folder, never into the repository.
- **Rosetta:** on Apple silicon this binary needs Rosetta, the app itself does not.
- **On errors with a device:** choose "Help > Create Support Package…" in the app (or the button in the error message) and send the ZIP. The diagnostic capture is always on and included in the package; it also serves as a test fixture.

## Before every release

- [ ] **Start without Rosetta** (`remove-gpsbabel` 3.3).
  - Start the release build on an Apple silicon Mac without Rosetta and on an Intel Mac.
  - Check: no Rosetta dialog appears, file mode and direct mode work.
- [ ] **Source code address** (`gpl-driver-package` 6.2).
  - Decided on 2026-11-13: `GPSLOADER_SOURCE_CODE_URL` is `https://github.com/mytracks/gpsloader`.
  - Check: the repository is public, and the state of the release is pushed there.
  - Sources of gpsbabel and Qt no longer need to be there, because neither is shipped anymore.
  - Check: `Scripts/verify-bundle.sh` passes for the release build, and the link in the About window opens the source.

## Direct mode – developer

- [ ] **Release 0.1.0 from GitHub** (`split-repositories` 6.2): download `myTracks-Loader-0.1.0.zip` from https://github.com/mytracks/gpsloader/releases/tag/0.1.0 on an Apple silicon Mac and an Intel Mac, unzip it, start it and read a device. Check: the app starts without a Gatekeeper warning, and reading succeeds.

- [ ] **SkyTraq** (`skytraq-device-port` 3.2): read and erase a SkyTraq logger. Check: number of points and times as with gpsbabel (`-i skytraq`), the logger is empty afterwards.
- [ ] **MTK and Holux** (`mtk-device-port` 3.2): read and erase an MTK logger (for example Qstarz) and a Holux M-241. Check: results as with gpsbabel, and logging continues afterwards.
- [x] **Main window** (`main-window-sections` 2.2): toggle in the toolbar (both segments readable, in light and dark mode: confirmed by the developer on 2026-11-19; in the snapshots of the debug automation the label of the selected segment is missing, which is caused by the capture), ⌘1/⌘2, drag and drop from the Finder in both sections, click on the drop zone. Check: flow as in the specs `app-shell` and `file-conversion`. Result: all confirmed by the developer on 2026-11-19 (labels light/dark, ⌘1/⌘2, drag and drop from the Finder, click on the drop zone).
- [ ] **Ports and hints** (`device-ports-and-hints` 4.2): plug in the Holux M-241 by USB and pair it over Bluetooth.
  - Check: both ports have readable names; with the Bluetooth port chosen the hint "connect via USB" appears.
  - Check: the four driver pages (Silicon Labs, Prolific, FTDI, WCH; `USBSerialChip` in `Packages/GPSLoaderKit/Sources/DeviceDrivers/PortPresentation.swift`) open in the browser.
- [x] **App icon** (`rename-and-icon` 3.4): look at `myTracks Loader.app` in the Finder and in the Dock on macOS 27 and, if available, on macOS 12–15. Check: the icon is not shrunk into a gray area and fits next to myTracks Neo. Result: fine, confirmed by the developer on 2026-11-19.
- [ ] **Support package** (`support-package` 4.2): after a real read (for example Holux M-241) choose "Help > Create Support Package…". Check: the ZIP opens in the Finder, and system, log, ports and the capture of the operation are complete and readable.
- [ ] **Week rollover** (`device-week-rollover` 3.2): read again the Holux M-241 whose times were 1024 weeks too early. Check: the times in the GPX are in the right year.
- [ ] **Wintec** (`wintec-device-port` 3.2): read a WBT-201 or G-Rays 2. Check: result as with gpsbabel (`-i wbt`).
- [ ] **Magellan** (`magellan-port` 3.2): read a Meridian or SporTrak over serial. Check: track and waypoints as with gpsbabel (`-t -w -i magellan`).

## Direct mode – users

The developer has no i-GotU and no Bluetooth loggers.

- [ ] **Read i-GotU** (`igotu-driver` 3.2): read a GT-800 and a USB model (for example GT-120).
  - Check: the USB model is found over HID. If the app reports "device not found", another USB access is needed.
  - Check: the points match @trip PC or igotu2gpx.
- [ ] **Erase i-GotU** (`igotu-driver` 3.3), experimental. Check: afterwards the device reports 0 records.
- [ ] **Locosys** (`navilink-device-port` 2.2): read a GT-31 in NAVILINK mode. Check: waypoints and track as with gpsbabel (`-i navilink`).
- [ ] **GNS 2000 / GNS 2000 plus** (`gns2000-driver` 5.2): pair it in System Settings, read and erase it in the app.
  - Check: the Bluetooth permission dialog appears once with the explanation text.
  - Check: the points match myTracks or the vendor software; after erasing the memory is empty.
  - Note byte 15 of the records (probably a checksum), ideally from a diagnostic capture.
- [ ] **XAiOX iTrackU** (`itracku-port` 2.2): read over Bluetooth or USB.
  - Check: points as with gpsbabel (`-t -i itracku`).
  - gpsbabel discards the last records that arrive together with the end marker. The app then has a few points more.

## File mode – developer

- [ ] **Columbus V-900, Visiontac, iBlue CSV** (`csv-logger-import` 6.2).
  - Check: number of points, times (UTC or local time?), elevations and waypoints are plausible and as with gpsbabel.
  - Note deviating header lines.
- [ ] **MTK and Holux memory image** (`mtk-bin-port` 5.2): convert a `data.bin` of iBlue 747/Qstarz and of Holux M-241. Check: number of points, times and positions as with gpsbabel.
  - The app writes no image when reading. It results from reading with gpsbabel (`-i mtk` or `-i m241`, file `data.bin`) or comes from existing backups.
- [ ] **SkyTraq memory image** (`skytraq-bin-port` 5.2): convert an image from `gpsbabel -i skytraq,dump-file=venus.bin`. Check: as with gpsbabel.
- [ ] **Wintec** (`wintec-file-port` 5.2): convert a TES file (WBT-202) and, if available, a BIN or TK1 file. Check: number of points, times and elevations as with gpsbabel.
- [ ] **Locosys SBP and SBN** (`locosys-file-port` 5.2). Check: the files are recognized; number of points, times and positions as with gpsbabel.
- [ ] **Medion GoPal** (`gopal-port` 5.2): convert a `.trk` file. Check: date, times, positions and speed are plausible.
- [ ] **Magellan SD card** (`magellan-port` 3.2): convert a `.log` or `.upt` file of a Meridian or eXplorist. Check: as with gpsbabel.
- [ ] **Alan Map500** (`alan-port` 3.2): convert a real `.trl` file.
  - Check: the file is recognized. The detection only checks whether the coordinates are plausible.
  - Check: tracks and points as with gpsbabel (`-t -i alantrl`).
- [ ] **KML and KMZ** (`kml-import` 5.3): convert existing exports from myTracks, Google Earth or logger programs.
  - Check: tracks, number of points and elevations as with gpsbabel (`-i kml`).
  - Note files in which time-stamped points appear as waypoints instead of a track (candidates for stage B).
  - Note KMZ files that are not recognized.
