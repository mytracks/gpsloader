# GPSLoggerKit

Native Swift reader for GPS logger file formats (and, later, logger protocols), producing a common
data model and GPX 1.1 output.

- Platforms: macOS 12+, iOS/iPadOS 27+. File formats and GPX output work on both; device transports
  (serial, HID, Bluetooth) will be macOS only.
- Swift 6 language mode, no third-party dependencies.
- License: MIT (see `LICENSE`).

## Formats

| ID | Format | Read | Notes |
|---|---|---|---|
| `nmea` | NMEA 0183 | yes | RMC, GGA, GLL, GSA, VTG, ZDA, WPL; any talker |
| `gpx` | GPX 1.0 / 1.1 | yes | tracks and waypoints; routes are ignored |

Output is always GPX 1.1 (`GPXWriter`).

## Usage

```swift
import GPSLoggerKit

let input = try FileInput.load(url)
guard let format = FileFormats.detect(prefix: input.data, fileName: input.name) else { /* unknown */ }
let result = try await FileFormats.read([input], format: format, options: ImportOptions())
let gpx = GPXWriter(creator: "MyApp 1.0").data(for: result.recording, createdAt: Date())
```

`result.warnings` reports skipped or damaged records, grouped by kind with a count.

## Clean-room rule

This package is MIT licensed and must not contain code derived from GPL or CC-BY-SA sources
(for example gpsbabel or igotu2gpx). Formats are implemented from public specifications, the
author's own code, and black-box observation (sample files, recorded device dialogs, output of
other programs). `PROVENANCE.md` lists the sources for every format; a test enforces that every
format in the catalog has an entry.

## Tests

```sh
swift test
xcodebuild test -scheme GPSLoggerKit -destination 'platform=iOS Simulator,OS=27.1,name=iPhone 17'
```
