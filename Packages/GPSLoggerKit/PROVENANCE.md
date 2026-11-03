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
