# Provenance

Sources used for each format in GPSLoggerKit. No GPL or CC-BY-SA licensed source code was
read, translated, or copied. Each section heading is the format ID used in the catalog.

## Common

- **GPS week rollover correction** (`RecordingProcessing.correctingWeekRollover`): behavior of the
  author's own myTracks code (`DsTrackFramework/Source/Classes/ImportExport/TrackLibraryGPX.m`,
  ca. lines 120–135): while a time lies more than 512 weeks in the past, add 1024 weeks.
- **Waypoints as track** (`RecordingProcessing.waypointsAsTrack`): behavior of the author's own
  myTracks file import (fallback when a file contains no tracks).
- **Civil date arithmetic** (`UTCTime.days`): "days from civil" algorithm by Howard Hinnant,
  published as public domain (<https://howardhinnant.github.io/date_algorithms.html>).

## `nmea`

- Sentence layouts (RMC, GGA, GLL, GSA, VTG, ZDA, WPL), the address field (talker + type), the
  checksum (XOR of all characters between `$` and `*`, two hex digits) and the `ddmm.mmmm`
  coordinate notation follow the publicly available descriptions of NMEA 0183, in particular
  "NMEA Revealed" by Eric S. Raymond (<https://gpsd.gitlab.io/gpsd/NMEA.html>, a document, not
  code) and the NMEA 0183 sentence reference in receiver manuals (e.g. u-blox and NovAtel
  protocol specifications). The NMEA 0183 standard itself was not used.
- Skipping lines that start with `@` (Sony GPS CS-1/CS-3) and merging several files into one
  track: behavior of the author's own myTracks code
  (`myTracks/Source/Classes/Controller/MyTracksMainController.m`, `convertNMEAFile:`, ca. lines
  1883–1903, and the file import around line 1934).
- Epoch merging, date continuation over midnight, back-dating of points before the first date,
  the two-digit year window 1980–2079 and segmentation are own design decisions
  (`openspec` change `gpsloggerkit-foundation`, design D5).
- Test fixtures are synthetic (invented coordinates), generated for this package.

## `gpx`

- GPX 1.1 schema: <http://www.topografix.com/GPX/1/1/gpx.xsd> (TopoGrafix, published for free use).
- GPX 1.0 schema: <http://www.topografix.com/GPX/1/0/gpx.xsd>; used for the GPX 1.0 elements
  `speed` and `course`.
- Date/time values: XML Schema `dateTime` (W3C XML Schema Part 2) / ISO 8601.
- The GPX writer is the author's own code from gpsloader (`setup-foundation`).
- Test fixtures are synthetic.

## `igc`

- FAI/IGC: "Technical Specification for IGC-approved GNSS Flight Recorders", Appendix A (data file
  format: A, H, I and B records, `HFDTE` in both the old `ddmmyy` and the newer `DATE:ddmmyy,nn`
  form, extension code `SIU`). Published by the FAI International Gliding Commission on fai.org.
- No third-party IGC reader (e.g. gpsbabel `igc.cc`) was consulted. myTracks had no IGC code of its
  own; it called gpsbabel.
- Test fixtures are synthetic, written by hand following the specification.

## `fit`

- Garmin "FIT Protocol" description (developer.garmin.com/fit/protocol): file header (12/14 bytes,
  data size, `.FIT`, header CRC), record header (normal and compressed timestamp), definition and
  data messages (architecture byte, field and developer field definitions), base types with their
  invalid values, the FIT epoch (1989-12-31T00:00:00Z) and the CRC-16 checksum. The checksum is
  implemented as CRC-16/ARC (reflected polynomial 0xA001, initial value 0), which the FIT
  algorithm is equivalent to.
- FIT profile, version 21.218.0 (Garmin FIT SDK, published under the FIT Protocol License), used
  only for message and field numbers, base types, scale and offset: `record` (20) fields 0, 1, 2,
  6, 73, 78, 253; `event` (21) fields 0 and 1 with `event` `timer` = 0 and `event_type` `start` = 0,
  `stop` = 1, `stop_all` = 4; `course` (31) field 5; `course_point` (32) fields 1, 2, 3, 6. The
  numbers were checked against `src/profile.js` of github.com/garmin/fit-javascript-sdk; no SDK
  decoder code was used.
- Not consulted: gpsbabel `garmin_fit`, `fit2tcx` and its `Garmin/FIT.pm` (myTracks resources,
  third-party Perl code).
- Test fixtures are synthetic, produced by the test encoder of this package.

## `tcx`

- Garmin Training Center Database schema v2:
  <https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd> and the activity extension
  <https://www8.garmin.com/xmlschemas/ActivityExtensionv2.xsd> (`TPX/Speed`).
- Turning courses into named tracks follows the behavior of the author's myTracks configuration
  (gpsbabel `-i gtrnctr -x transform,rte=trk` in `gpslogger.plist`); gpsbabel's source was not read.
- Test fixtures are synthetic.

## `suunto-sml`

- There is no public specification. The layout (root `sml`, `DeviceLog/Samples/Sample`, sample
  types `periodic`, `gps-base`, `gps-small`, radians for `Latitude`, `Longitude` and `GPSHeading`,
  `UTC` timestamps, `Events/Pause/State`) was derived by black-box observation of a sample file
  shipped with myTracks (`suuntoconvert/ambit.xml`). Only element names, sample types and units were
  taken; no values from that file are used in code or tests.
- The converter script next to it (`ambit2gpx.py`, from the Google Code project ambit2gpx, license
  unknown) was not read.
- Using the barometric altitude of the latest periodic sample (at most 60 s old) is an own design
  decision (`openspec` change `fit-tcx-suunto-import`, design D5).
- Test fixtures are synthetic.

## `kml`

- OGC KML 2.2 (OGC 07-147r2) with the schema `ogckml22.xsd`
  <http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd>, and Google's KML extension reference with
  the schema `kml22gx.xsd` <https://developers.google.com/kml/schema/kml22gx.xsd> (`gx:Track`,
  `gx:MultiTrack`, `gx:coord`, `gx:altitudeMode`). The older namespaces
  `http://earth.google.com/kml/2.0`, `2.1` and `2.2` follow Google's KML reference.
- KMZ: PKWARE's public ZIP specification `APPNOTE.TXT` (local header, central directory, end of
  central directory, methods 0 and 8, flag bits 0 and 3). DEFLATE (RFC 1951) is decoded by Apple's
  `Compression` framework. CRC-32 uses the published polynomial 0xEDB88320 (ISO 3309).
- The structure of myTracks' own KML export (namespace `http://earth.google.com/kml/2.2`, paths as
  `LineString` without `altitudeMode`) comes from the author's myTracks code (`Track.m`,
  `TrackPoint.m`, `TrackKML.m`).
- The structure of gpsbabel's KML output was observed on 2026-11-04 by running the gpsbabel 1.7.0
  binary on synthetic GPX files (`-o kml`, `-o kml,points=0`, `-o kml,trackdata=0,points=0`); its
  source was not read. Observed: a track folder per track with a `Placemark` named `Path` and, by
  default, a `Points` folder with one time-stamped placemark per track point; no `altitudeMode`.
  The fixture `gpsbabel.kml` is such an output for synthetic data.
- Cross-check against gpsbabel 1.7.0 reading the fixtures (`-i kml`, 2026-11-04): positions and point
  counts agree for all KML fixtures. Intended differences:
  - gpsbabel makes one track per `LineString` or `gx:Track` named after the placemark (`Path`);
    GPSLoggerKit makes one track per placemark with a segment per path and names gpsbabel's tracks
    after their folder.
  - gpsbabel turns the `Points` folder into waypoints and leaves the track without times;
    GPSLoggerKit gives the track the times (design D5) and creates no waypoints from it.
  - gpsbabel keeps altitudes under `clampToGround`; GPSLoggerKit drops them (spec `kml-import`,
    "Höhe").
  - gpsbabel copies a waypoint's name into its description; GPSLoggerKit leaves the comment empty.
- Test fixtures are synthetic.

## `v900`

- The Columbus V-900 user manual (section "Track Log") lists the recorded values: date, time,
  latitude, longitude, altitude, speed, direction, voice, positioning mode, positioning type, PDOP,
  HDOP and VDOP.
- The OpenStreetMap wiki pages "Columbus" and "Visiontac VGPS-900" state as facts that the logs are
  CSV files with fixed-length, NUL-terminated fields, that the header contains `INDEX`, `TAG`, `N/S`,
  `E/W` and `VOX`, and that voice recordings are stored as `VOX<n>.WAV`. Only these facts were used;
  no text or script was copied.
- The column names come from the header line of the files themselves.
- Black box, 2026-11-13: the gpsbabel 1.7.0 binary read synthetic files (`-i v900 -o gpx`); its
  source and documentation were not read. Observed: simple-mode header
  `INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT,SPEED,HEADING,VOX`, NUL padding and CRLF
  accepted, `YYMMDD`/`hhmmss` read as UTC, hemisphere letter after the number, `SPEED` in km/h,
  `HEADING` as course, rows tagged `C` and `V` become a track point and a waypoint (`VOX00003.WAV`),
  professional-mode columns `FIX MODE,VALID,PDOP,HDOP,VDOP` with `2D`/`3D` as fix type. gpsbabel
  checks the line length; the fixture `v900-pro.csv` uses field widths it accepts.
- Cross-check against gpsbabel 1.7.0 reading the fixtures (2026-11-13): point counts, positions,
  times, altitudes, speeds and courses agree. Intended differences:
  - gpsbabel names button markers `WPT001`, …; GPSLoggerKit names them `POI 1`, … (spec
    `csv-logger-import`, "V-900-Markierungen").
  - gpsbabel reports `VALID` = `DGPS` as fix `3d` and drops the DOP values; GPSLoggerKit reports
    `dgps` and keeps PDOP, HDOP and VDOP.
- Test fixtures are synthetic.

## `iblue-csv`

- The column names come from the header line of the files themselves; columns are found by name.
- Black box, 2026-11-13: the gpsbabel 1.7.0 binary wrote a synthetic GPX file as `-o iblue747` and
  `-o iblue757` and read synthetic files with `-i iblue747`; its source, its style definitions and
  its documentation were not read. Observed: header
  `INDEX,RCR,DATE,TIME,VALID,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT,SPEED,HEADING,DSTA,DAGE,PDOP,HDOP,VDOP,NSAT (USED/VIEW),SAT INFO (SID-ELE-AZI-SNR),DISTANCE,`,
  date `YYYY/MM/DD` (747) or `DD/MM/YYYY` (757), time `hh:mm:ss`, `VALID` `3d`/`2d`/`DGPS`,
  `SPEED` in km/h, integer heights in meters, unknown DOP written as `0.000000` and an unknown
  satellite count as `-1(`. Western longitudes are written with a minus sign and `W`; gpsbabel
  reads them as negative. `RCR` = `B` creates no waypoint.
- The fixtures `iblue747.csv` and `iblue757.csv` are gpsbabel's output for the synthetic
  `iblue-source.gpx`.
- Cross-check against gpsbabel 1.7.0 reading the fixtures (2026-11-13): point counts, positions,
  times, altitudes, speeds, fix types, satellites and DOP values agree. Difference: gpsbabel reads
  the columns at fixed positions; GPSLoggerKit finds them by name, so other column orders work too.

## Device interface and protocols

Not file formats; listed here because they are part of the package.

### Device interface (`DeviceConnection`, `DeviceProtocol`)

- The author's own code, written for gpsloader (change `device-mode`) and moved here from GPSLoggerKitGPL
  (change `gns2000-driver`). It contains no ported code.

### `GNS2000Device`

- Basis: the author's own myTracks driver (`DsTrackFramework/Source/Classes/GpsDriver/GNS2000.m` and
  `GNS2000.h`, © 2013 Dirk Stichling), written anew in Swift; no third-party source (e.g. gpsbabel's LOCUS
  code) was read.
- Taken over: sentences with XOR checksum (sent in lower case), waiting for the first NMEA sentence,
  `$PGNS,R` with `$PMTKLOX,0/1/2`, the 16-byte record (time, fix type 1–4, float latitude and longitude,
  height), skipping all-`FF` records, a new track when the time goes backwards, `$PGNS,C` confirmed by
  `$PMTK001` with a repeated request after more than 10 lines without `$P`.
- Changed (design D3 of change `gns2000-driver`): timeouts of 10 s (the old driver could wait forever);
  progress by packets; at most five erase requests; tracks named after the first point in UTC (the old app
  used the local time zone of its preferences); byte 15 of a record is still not evaluated.
- Tests use a simulated device; there was no hardware.
