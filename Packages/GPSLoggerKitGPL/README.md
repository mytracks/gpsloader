# GPSLoggerKitGPL

File formats and logger drivers for gpsloader that are ported from sources under the GNU GPL or a
license compatible with it. It complements [GPSLoggerKit](../GPSLoggerKit), which stays MIT licensed
and clean-room.

- License: **GPL-3.0-or-later** (see `LICENSE`). Any app that links this package is, as a whole,
  covered by the GPL and must offer its complete source code.
- Platform: macOS 12+. There is no iOS support: the App Store terms are not compatible with the GPL.
  Formats meant for iOS belong in GPSLoggerKit.
- Dependencies: GPSLoggerKit and the system libraries only. GPSLoggerKit never depends on this package.

## Formats

| ID | Format | Source |
|---|---|---|
| `skytraq-bin` | SkyTraq Venus 5/6 logger memory dump (`.bin`) | GPSBabel 1.7.0 `skytraq.cc` |
| `mtk-bin` | MTK logger memory dump, e.g. iBlue 747, Qstarz BT-Q1000 (`data.bin`) | GPSBabel 1.7.0 `mtk_logger.cc` |
| `m241-bin` | Holux M-241 / GPSport 245 memory dump (`.bin`) | GPSBabel 1.7.0 `mtk_logger.cc` |
| `wbt-tk1` | Wintec WBT-201 / G-Rays 2 / WSG-1000 TK1 file (`.tk1`) | GPSBabel 1.7.0 `wbt-200.cc` |
| `wbt-bin` | Wintec WBT-100/200 memory dump (`.bin`) | GPSBabel 1.7.0 `wbt-200.cc` |
| `wintec-tes` | Wintec WBT-202 TES file (`.tes`) | GPSBabel 1.7.0 `wintec_tes.cc` |
| `sbn` | Locosys GT-11/GT-31/BGT-31 SiRF binary log (`.sbn`) | GPSBabel 1.7.0 `sbn.cc`, `navilink.cc` |
| `sbp` | Locosys GT-11/GT-31/BGT-31 datalogger file (`.sbp`) | GPSBabel 1.7.0 `sbp.cc`, `navilink.cc` |
| `gopal` | Medion GoPal track log (`.trk`) | GPSBabel 1.7.0 `gopal.cc` |
| `magellan` | Magellan Meridian / eXplorist SD card files (`.log`, `.upt`) | GPSBabel 1.7.0 `magproto.cc` |
| `alantrl` | Alan Map500 track logs (`.trl`) | GPSBabel 1.7.0 `alan.cc` |

## Device protocols

Protocols implement `DeviceProtocol` on a `DeviceConnection` provided by the app (serial port, USB HID or a
simulation in tests).

| Protocol | Devices | Source |
|---|---|---|
| `SkyTraqDevice` | SkyTraq Venus 5/6 loggers (Canmore GT-730FL, Navin MiniHomer, …) | GPSBabel 1.7.0 `skytraq.cc` |
| `MTKDevice` | MTK loggers (iBlue 747, Qstarz, …), Holux M-241/GPSport 245 | GPSBabel 1.7.0 `mtk_logger.cc` |
| `WintecDevice` | Wintec WBT-100/200/201, G-Rays 2, WSG-1000 | GPSBabel 1.7.0 `wbt-200.cc` |
| `NavilinkDevice` | Locosys GT-11/GT-31/BGT-31, NaviGPS (NAVILINK mode) | GPSBabel 1.7.0 `navilink.cc` |
| `MagellanDevice` | Magellan Meridian, SporTrak | GPSBabel 1.7.0 `magproto.cc` |
| `ITrackUDevice` | XAiOX iTrackU (serial or Bluetooth) | GPSBabel 1.7.0 `itracku.cc` |
| `IGotUDevice` | i-GotU GT-800 (serial), GT-100/120/200/200e/600 (USB HID) | own myTracks code, igotu2gpx 0.3.0 |

## Usage

```swift
import GPSLoggerKit
import GPSLoggerKitGPL

let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
```

`GPLFileFormats.credits` lists the source projects for the app's about window.

## Rules for ports

1. **One package per family.** Each logger family is implemented either clean-room in GPSLoggerKit
   or as a port here, never in both. The assignment is recorded in `openspec/config.yaml`.
2. **When GPL source may be read.** Only in a change that assigns the family to this package, and
   only for that family. Work on GPSLoggerKit never reads GPL source. If a port needs something new in
   GPSLoggerKit, it is added there in a general form without code from the source; helpers otherwise
   live here.
3. **No way back.** Once GPL source of a family has been read, the family stays in this package.
4. **Compatible licenses only.** Allowed: GPL-2.0-or-later, GPL-3.0(-or-later), LGPL-2.1-or-later,
   CC BY-SA 4.0, MIT, BSD, Apache 2.0, public domain. Not allowed: GPL-2.0-only, CC BY-SA up to 3.0,
   custom licenses and sources without a license, unless the authors grant a compatible license.
5. **Version of the source.** For gpsbabel, tag `gpsbabel_1_7_0`, matching the binary of the old app (myTracks).
   Sources are downloaded to a scratch directory, never added to the repository.
6. **File header** of every ported file:

   ```swift
   // Ported from <project> <path> (<tag or commit>).
   // Original: Copyright (C) <years> <authors>, <license of the source>.
   // Translated to Swift and modified for gpsloader by Dirk Stichling, <YYYY-MM-DD>.
   // SPDX-License-Identifier: GPL-3.0-or-later
   ```

7. **Provenance.** `PROVENANCE.md` has a section per format (enforced by a test), and `credits`
   has an entry for every source project.

## Tests

```sh
swift test
```

Cross-checks against gpsbabel: the app no longer contains gpsbabel. Ports are compared with the gpsbabel 1.7.0
binary of myTracks (git history of the myTracks repository, commit `e0d1f18`, with `QtCoreGpsBabel.framework`),
copied to a temporary directory and never into this repository. Fixture tests write their GPX for the comparison
when `GPSLOGGERKITGPL_COMPARE_DIR` is set; device protocols are compared with a simulated device on a pseudo
terminal.
