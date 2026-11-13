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
| `igc` | IGC (FAI flight recorder) | yes | B fixes with date from `HFDTE`, satellites from `SIU`; one track per file; task (C records) ignored |
| `fit` | Garmin FIT | yes | `record` positions, altitude and speed; timer stops split segments; course name and `course_point` waypoints; chained files; bad CRC or truncation is a warning; sport data ignored |
| `tcx` | TCX (Garmin Training Center v2) | yes | one track per activity (segment per `Track`), courses as named tracks, `CoursePoint` waypoints, TPX speed; workouts and multisport ignored |
| `suunto-sml` | Suunto SML (Ambit, `.sml`/`.xml`) | yes | GPS samples (radians), barometric altitude of the latest periodic sample (≤ 60 s) else GPS altitude, pauses split segments; one track per file |
| `kml` | KML / KMZ (Google Earth) | yes | one track per placemark (segment per `LineString`/`gx:Track`), `Point` waypoints; times from `gx:Track` and from gpsbabel's `Points` folder; altitude unless ground-relative; KMZ: `doc.kml`, stored or deflate |
| `v900` | Columbus V-900 / Visiontac VGPS-900 (`.csv`) | yes | simple and professional mode, NUL-padded fields; UTC; one track per file; button markers (`C`, `D`) and voice recordings (`V`) also become waypoints |
| `iblue-csv` | iBlue 747/757 CSV export (`.csv`) | yes | columns found by header name; date `YYYY/MM/DD` or `DD/MM/YYYY`, UTC; fix type, DOP and satellites; one track per file |

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

### Adding formats

Formats of your own (or of another package) can be combined with the built-in ones in a
`FormatCatalog`. The built-in formats stay first; identifiers must be unique.

```swift
let catalog = FormatCatalog.standard.adding([MyFormat()])
if let format = catalog.detect(prefix: input.data, fileName: input.name) {
    let result = try await FileFormats.read([input], format: format)
}
```

## Clean-room rule

This package is MIT licensed and must not contain code derived from GPL or CC-BY-SA sources
(for example gpsbabel or igotu2gpx). Formats are implemented from public specifications, the
author's own code, and black-box observation (sample files, recorded device dialogs, output of
other programs). `PROVENANCE.md` lists the sources for every format; a test enforces that every
format in the catalog has an entry.

Ports from GPL sources are never added here. In gpsloader they live in the separate package
`GPSLoggerKitGPL` (GPL-3.0-or-later), which builds on this package's `FormatCatalog`; this package
does not depend on it.

## Tests

```sh
swift test
xcodebuild test -scheme GPSLoggerKit -destination 'platform=iOS Simulator,OS=27.1,name=iPhone Duo'
```
