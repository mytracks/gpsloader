# Analysis: GPS logger functionality in myTracks (old app)

This document summarizes how myTracks reads GPS loggers today. It serves as the functional reference for the
reimplementation in myTracks Loader (repository gpsloader). The original code is in `input/mytracks4mac/`. The folder
is not versioned (`.gitignore`), so all relevant details are recorded here. Paths in this document are relative to
`input/mytracks4mac/`.

In addition: [legacy-device-catalog.md](legacy-device-catalog.md) contains all 143 device entries of the current
version. Devices that were removed in earlier versions (i-GotU, Wintec WPL 1000) are described here in sections 3.2
and 4.

Which parts myTracks Loader takes over is not decided here but in `openspec/config.yaml`.
This document only describes the behavior of the old app.

The old app is a Git repository. Deleted code can be retrieved with `git show <commit>^:<path>`.
Important commits:

| Commit | Date | Content |
|---|---|---|
| `b1ac5a3` | 2016-06-11 | initial checkin (the history starts here) |
| `fdb8054` | 2025-02-04 | myTracks 4.4.0, gpsbabel 1.9.0 (universal) |
| `e0d1f18` | 2025-04-19 | "rollback of gpsbabel": back to gpsbabel 1.7.0 (myTracks 4.4.3) |
| `3cbc727` | 2026-10-19 | myTracks 4.5.0: Intel support, i-GotU and WPL 1000 removed, gpsbabel 1.10.0 |

---

## 1. Overview and terms

myTracks knows three **GPS modes** (`GpsMode` in `DsUtilities/.../DsPreferences`):

| Mode | Meaning | Relevance for myTracks Loader |
|---|---|---|
| `GpsModeDirect` | The device is attached serially (USB serial adapter or Bluetooth SPP) and is read actively | **core** |
| `GpsModeUsbStorage` | The device is mass storage or an SD card; files are chosen and converted | **core** (file mode) |
| `GpsModeLoadMyTracks` | Reading through the third-party app *LoadMyTracks* (ScriptingBridge, `com.ClueTrust.LoadMyTracks`) | **not taken over** |

A **logger configuration** consists of:

- `device`: name of the serial device **without** the `/dev/cu.` prefix (for example `SLAB_USBtoUART`, `usbmodem1421`).
  Special value `auto` for devices that need no device choice.
- `deviceType`: driver string. It encodes the driver type (see section 3).
- `additionalArguments`: additional arguments for gpsbabel (see 3.1).
- `gpsFileFormat` and `gpsFileAdditionalArguments`: only for the file mode.

Several named configurations are stored in the user defaults
(`myTracks/Source/Classes/NewControllers/LoggerConfiguration/LoggerConfigurations.swift`).
Keys: `LoggerConfigurationsCount`, `LoggerConfigurationName<i>`,
`LoggerConfigurationDeviceType<i>`, `LoggerConfigurationDevice<i>`,
`LoggerConfigurationAdditionalArguments<i>`, `LoggerConfigurationGpsFileFormat<i>`,
`LoggerConfigurationGpsFileAdditionalArguments<i>` and `LoggerConfigurationGpsMode<i>`.
myTracks runs in the sandbox (`info.stichling.myTracks`), so the values are in its container.
myTracks Loader does **not take over** these configurations.

## 2. Flow "Import data from logger" (direct mode)

Source: `myTracks/Source/Classes/Controller/MyTracksMainController.m`
(`importFromGPSDevice:`, `importFromGPSDeviceThread`, `deleteDataFromGPSDevice:`).

1. A background thread starts. The UI shows a non-modal progress panel without real progress.
2. `GPSBabel importTracksAndWaypointToFile:` writes a temporary GPX file (`device.gpxx` in Application Support).
3. The device names are corrected (`correctDeviceNameWithDynamicPrefix:`). For the prefixes
   `usbmodem` and `PL2303`: if `/dev/cu.<device>` no longer exists, the first `/dev/cu.<prefix>*` is taken.
   These device names change with the USB port.
4. The driver is chosen by `deviceType` (section 3).
5. The GPX file is imported into the track library. Post-processing follows (section 5).
6. Results or errors are reported as alerts. Texts:
   - "Error communicating with the GPS device. Please check connection and configuration."
   - "The import finished successfully. However no tracks have been created because your logger does not contain any GPS data."
   - "%d tracks have been imported." or "… already existing track(s) have been found."

**Erasing** (`deleteDataFromGPSDevice:`) is only allowed if one of the following conditions holds:

- The driver is `wbt*`, `m241*`, `mtk*` or `skytraq*`.
- The driver string contains `!DEL!`.
- It is an internal driver (`*…`).

Otherwise "Deleting is currently only supported for the wbt, mtk and skytraq driver." appears.

In addition there is `killAllRunningProcesses` (`killall gpsbabel`) as cancellation when the app quits.

## 3. Driver types (encoding in the `deviceType` string)

Source: `DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`.

### 3.1 gpsbabel drivers (no prefix)

The driver name is a gpsbabel input format. Call (shell through `system()`, working directory `$TMPDIR`):

```
gpsbabel -t -w -i <type>[<additionalArgs>] -f "/dev/cu.<device>" <filter> -o gpx -F <out.gpx>
```

- If `additionalArguments` starts with `,`, the part is appended directly to `-i <type>`.
  These are format options, for example `,baud=38400,initbaud=38400`. Otherwise it is appended to the end of the
  command line.
- `!FILTER!` in `additionalArguments`: everything after it is inserted as a gpsbabel filter (`-x …`).
- `#<suffix>` in the deviceType: `gpsbabel<suffix>` is called instead of `gpsbabel`. This is a leftover for several
  gpsbabel versions.
- Erasing: `-i <type>,erase<additionalArgs>`; for `skytraq` `-i skytraq,erase,no-output`.
  Allowed only for `wbt`, `mtk`, `skytraq` and `m241`. Otherwise the function returns the code 254.

gpsbabel drivers used in direct mode (see catalog):

| gpsbabel format | Devices (selection) | Erase | Note |
|---|---|---|---|
| `mtk` | Qstarz BT-Q1000/1300/BT-100, iBlue 747, Blumax GPS-4044, iTrek Z1, Photomate 887, Transystem 860E, Networx iGeo | yes | MediaTek chipset, very common |
| `m241` | Holux M-241, GPSport 245 | yes | MTK variant by Holux |
| `wbt` | Wintec WBT-100/200/201, G-Rays 2, WSG-1000 | yes | |
| `skytraq` | SkyTraq Venus, Canmore GT-730FL/740FL/750F, Conrad GT-730/750, Navin MiniHomer, Travel Honey, Gisteq DPL900, Dörr | yes | baud rate options `baud`, `initbaud` |
| `navilink` | Locosys GT-11/GT-31/BGT-31, NaviGPS | no | |
| `magellan` | Magellan SporTrak/Meridian | no | |
| `itracku` | XAiOX iTrackU | no | |

#### gpsbabel versions and format scope

From version 1.8 gpsbabel removed many old formats. Among them are exactly the logger drivers `wbt`,
`navilink`, `magellan` and `itracku` and the file formats `wintec_tes`, `sbp`, `sbn`, `gopal`,
`alantrl`, `wbt-bin` and `wbt-tk1`. This affects about 35 entries in the catalog.

| myTracks | gpsbabel | Architecture | removed formats present? |
|---|---|---|---|
| 4.4.0 | 1.9.0 | universal | no |
| 4.4.3 | **1.7.0** | x86_64 only | **yes**: "back to 1.7.0, because some file formats … are no longer supported" |
| 4.5.0 (current) | 1.10.0 | universal, from macOS 11 (Qt 6.5.3) | no |

⚠️ Consequence: in the current myTracks 4.5.0 the plist still offers the wbt, navilink, magellan and itracku devices,
but gpsbabel 1.10.0 no longer knows these formats. So these devices do not work there.

This was checked like this: the 1.10.0 from the current bundle was run (`gpsbabel -^1` lists 60 formats).
The binaries from the history were examined with `strings` for the format names.
1.7.0 contains all formats used in the catalog **except** `cetus` and `coto` (Palm OS).

**gpsbabel 1.7.0** (planned for myTracks Loader at that time, today only used for black-box cross-checks) is
available in two places:

- Git history, commit `e0d1f18`: `myTracks/Source/Resources/X86Only/gpsbabel1_7_0`
  (identical to `X86Only/gpsbabel` in this commit) and
  `myTracks/Source/Resources/X86Only/QtCoreGpsBabel.framework` (Qt 5.12.9).
- Working copy: `Import/Apps/GPSBabelFE170.app` (gpsbabel 1.7.0 with Qt 5 frameworks).
  `Import/install-gpsbabel170.sh` assembles `gpsbabel` and `QtCoreGpsBabel.framework` from it
  (install_name_tool + codesign with Developer ID).

Properties: Mach-O **x86_64**, minimum macOS 10.12. Linked against
`@executable_path/../Frameworks/QtCoreGpsBabel.framework/Versions/A/QtCoreGpsBabel`, CoreFoundation,
IOKit and DiskArbitration. On Apple silicon it needs **Rosetta 2**. Without Rosetta the start of a helper process
fails with "Bad CPU type in executable". There is no installation dialog.

### 3.2 Internal drivers (prefix `*`)

They are written in Objective-C and implement the protocol `GpsDriver`
(`DsTrackFramework/Source/Classes/GpsDriver/GpsDriver.h`):

```objc
- (NSString*) name;
- (NSArray*)  importTracksFromDevice:(NSString*)device options:(NSDictionary*)options;
- (BOOL)      deleteTracksFromDevice:(NSString*)device options:(NSDictionary*)options;
```

The track list is then exported as GPX, without myTracks extensions.

#### `*BG728` – Maptaq Trip IQ (`GpsDriver/BG728.m`)

- Serial through `AMSerialPort` (`GpsDriver/AMSerialPort/`, third-party library): **115200 baud, 8N1**, read timeout 30 s.
- ASCII line protocol in NMEA style, line end `\r\n`. The checksum is the XOR of all characters between `$` and `*`,
  as a two-digit hex number.
- Flow:
  1. `$BG728,0,3*3B` queries the time zone. Answer: commandId 3, argument 0 = time zone in **hours**.
  2. `$BG728,0,16*0F` queries the number of points. Answer: commandId 16, argument 0 = number.
  3. `$BG728,0,17,<n>*00` queries point *n* (0-based). The checksum is always sent as `00` here; the device
     apparently ignores it.
     Answer: commandId 17. Arguments: `n, hh:mm:ss, MMDDYY, lat, lon, ele`
     (example: `11:54:02`, `051712`, `51.741158`, `8.680967`, `94`).
     The year is `20YY`.
  4. Erasing: `$BG728,1,18*00`. Answer: commandId 18.
- Answer format: `$BG728,<commandCode>,<commandId>,<args…>*<cs>`.
- Error handling: on a wrong checksum, a foreign identifier or a non-matching answer the current request is sent again.
  After more than 128 read attempts without a matching answer the driver gives up. Read error code 100 (timeout) is
  tolerated.
- Result: **one** track. Name = time of the first point. The time zone offset (`timezone * 60` minutes) is stored on
  the track.
  ⚠️ Open: it is not clear whether the device time is UTC or local time. The old app interprets the ISO string without
  a zone. This has to be verified with real hardware.

#### `*GNS2000` – GNS 2000 / GNS 2000 plus (`GpsDriver/GNS2000.m`)

- **Bluetooth Classic through IOBluetooth**, not through `/dev/cu.*`. The device path is ignored.
  1. The device named `GNS 2000` or `GNS 2000 plus` is looked for in `IOBluetoothDevice.pairedDevices`.
  2. Close an existing connection, call `openConnection`, wait 2 s each.
  3. SDP query. Look for the service named `GNS GPS` and open its RFCOMM channel (`openRFCOMMChannelSync`).
- The protocol is MTK-based with NMEA-like lines and an XOR checksum. The device sends NMEA sentences continuously.
  The first line that starts with `$` counts as the signal "ready". Only then is the request sent.
  - Read: `$PGNS,R*<cs>`. Answers:
    - `$PMTKLOX,0,<packetCount>`: start.
    - `$PMTKLOX,1,<packetIndex>,<w1>,<w2>,…`: data. Every 4 hex words (8 hex characters) form a 16-byte record.
    - `$PMTKLOX,2`: end.
  - Erase: `$PGNS,C*<cs>`. Confirmation: `$PMTK001,…`. After more than 10 non-`$P` lines the request is repeated.
  - Version (unused): `$PGNS,V,3`.
- **16-byte record** (little endian):

  | Offset | Type | Content |
  |---|---|---|
  | 0 | UInt32 | Unix timestamp (UTC) |
  | 4 | UInt8 | fix type; only 1…4 are valid |
  | 5 | Float32 | latitude |
  | 9 | Float32 | longitude |
  | 13 | Int16 | altitude (m) |
  | 15 | UInt8 | (unused, probably a checksum) |

  Records of only `FF` count as empty and are skipped.
- **Track splitting**: if a timestamp is smaller than the previous one, a new track starts.
- Track names: time of the first point. The time zone comes from the app settings.
- Synchronization: the delegates run on the main thread, the caller waits through `NSCondition`.
  There is no timeout; the old app can hang.

#### i-GotU (Mobile Action), removed in myTracks 4.5.0

Source: `git show 3cbc727^:DsTrackFramework/Source/Classes/GpsDriver/IGotUGT800.m` (or `IGotU.m`)
and `git show 3cbc727^:myTracks/Source/Resources/gpslogger.plist`.

Catalog entries before the removal (all of type `usb`):

| Device | Driver | Erase |
|---|---|---|
| i-GotU GT-100, GT-120, GT-600 | external `igotu2gpx0.3.0 dump` or `clear` (shell command, `driverurl = skip`) | yes |
| i-GotU GT-200e | `igotu2gpx0.3.0 dump` | no |
| i-gotU GT-800 (and Pro) | internal driver `*i-gotUGT800` (`IGotUGT800.m`) | yes |

`igotu2gpx` is an external open source program (GPL). It was bundled in the versions 0.3.0 and 0.4.0
(Qt 4, boost, libusb 0.1/1.0, **x86 only**). The release note of 4.5.0 names "missing drivers for Apple silicon" as
the reason for the removal. In fact arm64 builds of these programs were missing; there was no kernel driver.

**Shared protocol** (identical in `IGotU.m` and `IGotUGT800.m`):

- Commands start with `0x93`. The last byte is the checksum: `(0 − sum of all previous bytes) mod 256`.
- An answer starts with `0x93`. Bytes before it are discarded.
- Commands (bytes after `0x93`, the rest padded with `00`):

  | Purpose | Command | Answer |
  |---|---|---|
  | Switch NMEA output | `93 01 01 <mode>`; mode 3 before reading, 0 afterwards | 3 bytes |
  | Identification (USB variant) | `93 0A` | 3 bytes, then 10 bytes: serial number LE32 in bytes 0–3, model in byte 7 (1 = GT-120, 2 = GT-200, 8 = GT-800) |
  | Model (GT-800) | `93 05 04 00 03 01 9F` | 6 bytes; byte 5 == `0x17` means GT-800 Pro |
  | Number of points | `93 0B 03 00 1D` | GT-800: 6 bytes, number = `((b[3] & 3) << 16) + BE16(b[4..5])`; USB: 3 bytes, number = `BE16(b[1..2])` |
  | Read memory | `93 05 07 <sizeHi> <sizeLo> 04 03 <pos 24 bit BE>` | 3 bytes, then `size` data bytes |

- The data starts at address `0x1000` and is read in blocks of `0x1000` bytes until `number × 32` bytes are reached.
- **Record, 32 bytes, big endian:**

  | Offset | Content |
  |---|---|
  | 0 | Flags: `0x04` waypoint, `0x10` navigation data invalid, `0x40` track start. The value `0xF1` marks a debug record with ASCII text from byte 6. |
  | 1 | high nibble: **year mod 16**; low nibble: month |
  | 2–3 | day = `b2 >> 3`; hour = `(b2 & 7) * 4 + (b3 >> 6)`; minute = `b3 & 0x3F` |
  | 4–5 | milliseconds (BE16); second = value / 1000 |
  | 8–11 | altitude from air pressure, Int32 / 100 |
  | 12–15 | latitude, Int32 / 1e7 |
  | 16–19 | longitude, Int32 / 1e7 |
  | 20–23 | GPS altitude, Int32 / 100 (used; the pressure altitude is disabled) |
  | 29 | low nibble: used satellites; high nibble: maximum satellites found |
  | 30 | "weight criteria" (unused) |

- Validity: not invalid, used satellites > 4 and maximum found > 0 (GT-800).
  The USB code only requires used satellites > 0.
- The flag "track start" starts a new track. Waypoints become track points with the name "WPT".
- ⚠️ The year is reconstructed relative to the current year (last 16 years). For very old data it is ambiguous.
- ⚠️ The time is interpreted without a zone. It is probably UTC; without a test device this is not verified.

**GT-800** (`IGotUGT800.m`): serial (`/dev/cu.*`) with **9600 baud, 8N1**, no flow control,
non-canonical mode, read timeout 5 s. A command is **16 bytes** long.
Erasing (`purgeMemory`):

1. From block `0x6FF` downwards to 1, each block is checked with `read memory` (16 bytes at `i × 0x1000`)
   until the first block is found that does not consist only of `FF`.
2. From this block on the following sequence is sent for every block:
   - `93 06 04 00 00 01 06`, expected answer `93 00 00`
   - `93 06 07 00 00 04 20 <pos 24 bit>`, expected answer 3 bytes
   - repeat `93 05 04 00 01 01 05` until the answer is `93 00 01 00`
3. Afterwards the user has to unplug the logger so that it restarts. The old app shows a hint for this.

The meaning of the write commands is not documented; in the code they are called `sendUnknownWriteCommand`.

**GT-100/120/200e/600** (template `IGotU.m`): USB vendor `0x0DF7`, product `0x0900`. Over USB the GT-800 has the
product ID `0x0B80`.

- A command is sent in **two 8-byte halves** as a control transfer:
  `bmRequestType 0x21, bRequest 0x09, wValue 0x0200, wIndex 0`. This corresponds to an HID `SET_REPORT`.
- The checksum is in the last byte of the second half and covers both halves.
- Answers come through the interrupt/bulk pipe.
- `IGotU.m` was **unfinished** and not used in any plist entry: the product ID is fixed to
  `0x0B80`, at most 12 blocks are read, and erasing is not implemented.
- Hypothesis, not verified: because it is an HID device, it can be used through IOHIDDevice without a kext.

### 3.3 Shell command drivers (prefix `!`)

The deviceType is a shell command line. An optional `!DEL!` separates the erase command:
`!<importCmd>!DEL!<deleteCmd>`. Placeholders (`replaceTemplates:` in `GPSBabel.m`):

| Placeholder | Replacement |
|---|---|
| `$BUNDLE` | path of the app bundle |
| `$APP_BUNDLE` | obsolete, becomes `$BUNDLE/Contents/Resources` (see `correctSetting:`) |
| `$TMPDIR` | temporary directory |
| `$DEVICE` | `/dev/cu.<device>` (quoted for the shell) |
| `$GPX` and `$GPX_NO_EXT` | target GPX file with or without extension |
| `$INPUTFILE` | input file (file mode) |

Success criterion of the import: the target file exists and is at least 10 bytes large.

Helper programs used (all below `myTracks/Source/Resources/`):

| Devices | Helper program | Language / license | Note |
|---|---|---|---|
| Royaltek RGM-3800, GOSGET S1, RBT-2300 | `rgm3800-rev25.py`, `rbt2300.py` (`-d $DEVICE trackx 0-` or `erase all`) | Python 2, GPLv3 (Karsten Petersen) | RBT-2300 has an additional field in `GetInfo` |
| Gisteq PhotoTrackr DPL700/CD111, XAiOX iTrackU (Nemerix/SiRF III) | `iTU4l/iTU4l.pl` + `iTU4l/sr2x.pl` (before that `stty 115200 cs8 raw`) | Perl, GPLv2 (Hartmut Schimmel) | variant through `-i p`, `-i n` or `-i s` |
| MainNav | `mainnav-reader-0.5/mainnavdist/…` | Python 2, BSD-2 (Dennis Keitzel) | erase with `-p` |
| Holux GPSport 245 (alternative) | two-stage: `gpsbabel -i m241` and then `-i m241-bin` | gpsbabel | |

⚠️ **Python 2 is no longer present since macOS 12.3, and Apple marked Perl as deprecated.**
These drivers effectively no longer work in the old app on current systems.

The variant "Holux GPSport 245 – alternative" is also a shell command but needs no script language:

1. `gpsbabel -i m241 -f $DEVICE -o csv -F $TMPDIRm241.csv`; as a by-product `data.bin` is created in the working directory.
2. `gpsbabel -t -w -i m241-bin -f $TMPDIRdata.bin -o gpx -F $GPX`

## 4. File mode (USB storage / SD card)

- The user chooses one or more files. They are converted with
  `gpsbabel -t -w -i <gpsFileFormat> -f <in> -o gpx -F <out> <args> 2>&1`, stderr is shown as the error text.
- If `gpsFileAdditionalArguments` starts with `!`, it is a shell command with placeholders (as in 3.3).
- **NMEA**: several files are concatenated before the conversion (`cat`), unless the user default
  `DoNotMergeNMEAFiles` is set. Lines that start with `@` are removed (Sony GPS CS-1/CS-3).
- If the result contains no tracks, a second attempt follows with `gpsbabel -i gpx … -x transform,trk=wpt`:
  waypoints become a track.
- Helper programs: `suuntoconvert/ambit2gpx.py` (Suunto Ambit XML/SML, Python 2), `wsg2000/wsg2000.c`
  (Wintec WSG-2000 `.NAL`, C, GPL/CC-BY-SA, Greg A. Woods), `fit2tcx` (Garmin).
  For TCX there is `-i gtrnctr -x transform,rte=trk`, for IGC `-i igc`.
  ⚠️ The IGC entry in the plist contains a typo (`i-o gpx` instead of `-o gpx`).
- The list of offered gpsbabel file formats (70 entries) is in `GPSBabel.m` (`gpsBabelFileFormats[]`).
- `cetus` and `coto` (Palm OS) are already missing in gpsbabel 1.7.0. These catalog entries are dead.

**WSG-2000 `.NAL`** (`myTracks/Source/Resources/wsg2000/wsg2000.c`, Greg A. Woods, CC-BY-SA/GPLv2):
a C program of its own (bundle ID `info.stichling.wsg2000`). The format consists of fixed records of **32 bytes**,
little endian:

| Field | Content |
|---|---|
| Flags (16 bit) | bit 0 track start, bit 1 waypoint |
| Time (32 bit, bit-packed) | second 6 bits, minute 6 bits, hour 5 bits (probably UTC) |
| Date (32 bit, bit-packed) | day 5 bits, month 4 bits, year 6 bits (+2000) |
| Latitude, longitude | Int32 / 1e7 |
| Altitude | UInt16, meters |
| Temperature | Int8, °C |
| Air pressure | UInt16, mbar |
| Cadence, heart rate | UInt8 |
| Incline | Int8, degrees |
| Compass, roll, yaw | Int16 |
| Speed | UInt8, km/h |
| User | UInt8, 0–3 |
| Padding | 16 bit |

The exact bit layout is in the structure `nal_data32_le` in `wsg2000.c`.
(This description comes from `wsg2000.c` and is therefore not a permitted source for the clean-room GPSLoggerKit.)

**Wintec WPL 1000 / Navilock NL-456DL Easy Logger**, removed in myTracks 4.5.0: file `nvpipe.dat` from the device.
It was read with `wpl1000reader`, an external program (C++, x86_64 only, Oliver Lau 2008/09, "all rights reserved",
**without source code**). The binary is still available at
`git show 3cbc727^:myTracks/Source/Resources/X86Only/wpl1000reader`; option `-m` creates one file per track.

## 5. Post-processing during the import

Source: `DsTrackFramework/Source/Classes/ImportExport/TrackLibraryGPX.m`, `GpxImportConfiguration`.

- **GPS week rollover correction**: if a point lies more than 512 weeks in the past, 1024 weeks are added. This is
  repeated until the condition no longer holds. Can be switched off with the user default `DontCorrectWeekRollover`.
  Relevant for older MTK loggers.
- **Time zone**: if no time zone is set on the track, the old app takes the time zone from the settings.
  In GPX times are always UTC; for myTracks Loader this is only relevant if devices return local time (BG728?).
- **Duplicate detection**: track ID `logger:<start>-<end>`. This is specific to myTracks and possibly not needed in
  myTracks Loader.
- GPX export without myTracks extensions (`GpxExportConfiguration.exportMytracksExtensions = NO`).

## 6. Device choice and setup assistant

Source: `myTracks/Source/Classes/Controller/GpsLoggerWizard.m`,
`NewControllers/Preferences/PrefGpsDevicesViewController.swift`.

- Device list: all entries `/dev/cu.*`.
- Assistant with a search over the device names from `gpslogger.plist`. The steps depend on the type:
  - **USB**: the user unplugs the device, and the existing `cu.*` are remembered. Then the user plugs it in,
    waits 5 s and sees a new `cu.*`. `SLAB_USBtoUART` is preferred. If nothing is found, the assistant links the
    driver download page (`driverurl`, generally `http://www.mytracks4mac.info/drivers`).
  - **Bluetooth**: the user chooses from the `cu.*` list (the device must be paired before).
  - `driverurl == "skip"`: no device choice, device `auto`.
- The USB serial chips of the loggers are typically Silicon Labs CP210x (`SLAB_USBtoUART`), Prolific PL2303
  (`PL2303-*`, `usbserial-*`) or CDC-ACM (`usbmodem*`). Until now vendor kexts were partly needed for them, which only
  run on Intel Macs. This is the reason for moving the logger functions out of myTracks.
  (Current macOS versions bring DriverKit drivers of their own for CP210x, PL2303, FTDI and CDC-ACM.
  Which devices work with them without additional drivers is still to be checked.)
- Bluetooth loggers, except the GNS2000, run exclusively through the serial port `/dev/cu.<name>` that macOS creates
  after pairing. The old app could not do more.

## 7. Functions not to be taken over

- Track library, maps, geotagging, duplicate detection, license check (`stripIfNoLicense`).
- LoadMyTracks connection (type `loadmytracks`, 37 devices, mainly Garmin).
- Real-time tracking (`RealtimeTracking.m`: `gpsbabel -T -i NMEA -f /dev/cu.<device> -o csv -F -`), unless explicitly
  requested.
- General GPX/KML/LOC/GPI conversions and `simplifyFile` from `GPSBabel.m`. They serve the track management, not
  reading loggers.
- Logger configurations from myTracks (section 1).
- All drivers based on script languages (section 3.3), and `ambit2gpx.py` and `fit2tcx` (Perl).

## 8. Known weaknesses of the old implementation (do not rebuild)

- Shell calls through `system()` and `popen()` with string concatenation (quoting and injection risk).
- No real progress display and no clean cancellation (only `killall gpsbabel`).
- GNS2000 can wait forever without a timeout. BG728 blocks synchronously in the read thread.
- Manual memory management (MRC) and Objective-C singletons.
- Dependency on Python 2 and Perl.
