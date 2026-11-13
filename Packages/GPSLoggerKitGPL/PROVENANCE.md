# Provenance

Sources of every format and driver in GPSLoggerKitGPL. Unlike GPSLoggerKit, this package may contain
code translated from sources under the GPL or another license compatible with GPL-3.0-or-later.

Each section heading is the format ID used in the catalog. A section names:

- every source the code is based on: project, file, tag or commit, copyright holders and license
  (quoted with file and line);
- own additions, public specifications and black-box observations used besides the source.

Every ported source file carries a header with the copyright notice of its source, the source's
license and the note that it was translated and modified for gpsloader, with the date.

## Shared helpers

`Support/ImportSupport.swift` (warnings, cancellation, byte access, GPS time, localization) is own code
and not derived from any source project. The GPS-UTC leap seconds are public IERS Bulletin C data.

## `skytraq-bin`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `skytraq.cc`, downloaded on 2026-11-13 as
  `https://github.com/GPSBabel/gpsbabel/archive/refs/tags/gpsbabel_1_7_0.tar.gz`
  (SHA-256 `30b186631fb43db576b8177385ed5c31a5a15c02a6bc07bae1e0d7af9058a797`).
- Copyright: `skytraq.cc` line 5 "Copyright (C) 2008-2019  Mathias Adam"; lines 7-9 name
  J.C Haessig (2008) and Josef Reisinger (2009, 2010).
- License: `skytraq.cc` lines 11-14 "either version 2 of the License, or (at your option) any later
  version" (GPL-2.0-or-later).
- Translated: constants (lines 36-39), `me_read32` (580-583), `gpstime_to_timet` (585-638),
  `ECEF_to_LLA` (640-664), item layouts (709-767), `process_data_item` (769-910),
  `process_data_sector` (912-927) and `file_read` (1385-1418). The serial driver and the options are
  not part of the port.
- Intended differences (design D4 of change `skytraq-bin-port`): unknown or cut-off items end the dump
  with a warning instead of a fatal error; a compact item without a preceding full item is skipped;
  multi-Hz items keep their milliseconds; multi-Hz POI items (type 0xC) also become waypoints; the
  track is named after the file and waypoints `POI n`; the leap-second offset switches exactly at the
  UTC instant (the source switches one second early).
- Cross-check against the gpsbabel 1.7.0 binary (`-i skytraq-bin`, 2026-11-13) with the synthetic
  fixture `venus.bin`: 516 track points in both; positions agree within 1e-7 degrees, altitudes within
  0.01 m, speeds and times agree except for the milliseconds of multi-Hz items; gpsbabel creates one
  waypoint (it skips the multi-Hz POI), GPSLoggerKitGPL two.
- Test fixture `venus.bin` is synthetic (written by the test encoder `SkyTraqTestDump`).

## `mtk-bin`

- Source: GPSBabel, tag `gpsbabel_1_7_0` (same archive as `skytraq-bin`), file `mtk_logger.cc`.
- Copyright: `mtk_logger.cc` line 4 "Copyright (C) 2007 Per Borgentun"; lines 5-6 "With lot of
  inspiration from wbt-200.c, Copyright (C) 2006 Andy Armstrong".
- License: `mtk_logger.cc` lines 8-11, GPL-2.0-or-later.
- Translated: event bits (lines 129-134), field table `log_type` (139-188), `LOG_RST` (118-122),
  `add_trackpoint` (804-923), `mtk_parse` (1113-1335), `mtk_parse_info` (1337-1419), `mtk_log_len`
  (1421-1452), `file_init`, `holux245_init`, `is_holux_string` (1460-1507) and `file_read`
  (1509-1661). The serial driver and the CSV output are not part of the port.
- Intended differences (design D4 of change `mtk-bin-port`): records with a wrong checksum are dropped
  with a warning (the source keeps them); only fix-less points at 90°/0° or 0°/0° are dropped (the
  source's condition drops nearly every fix-less point with a western longitude); fix 0x0008 (military)
  gives no fix type (the data model has no `pps`); records at the end of the file are read by their
  actual length; a block without 0xFF padding continues at 0x200 of the next block; tracks are named
  after the file (numbered when there are several), waypoints `POI n`.
- Cross-check against the gpsbabel 1.7.0 binary (`-i mtk-bin`, 2026-11-13) with the synthetic fixture
  `mtk.bin`: both give two tracks with 4 and 3 points and one waypoint; positions, altitudes, times
  (including milliseconds), fix types, satellites and HDOP agree.
- Test fixture `mtk.bin` is synthetic (test encoder `MTKTestDump`).

## `m241-bin`

- Source, copyright and license as for `mtk-bin` (`mtk_logger.cc`, device types `HOLUX_M241` and
  `HOLUX_GR245`): 4-byte coordinates, 3-byte heights, Holux identification strings, waypoint marker
  `WAYPNT`, swapped height and speed after `HOLUXGR245`/`HOLUXM1200`.
- Cross-check against the gpsbabel 1.7.0 binary (`-i m241-bin`, 2026-11-13) with the synthetic fixture
  `m241.bin`: 4 track points and one waypoint in both; positions, altitudes and times agree.
- Test fixture `m241.bin` is synthetic.

## `wbt-tk1`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `wbt-200.cc` (file reader shared by `wbt-bin` and
  `wbt-tk1`). Copyright: line 4 "Copyright (C) 2006 Andy Armstrong". License: lines 6-9,
  GPL-2.0-or-later.
- Translated: constants (lines 37-46), WBT-201 flags (59-63), `_SPLIT_DATE`, `decode_date`,
  `check_date` (502-535), `wbt200_data_chunk` (563-605), `is_valid` (608-642), `all_null` and
  `wbt201_data_chunk` (780-838), `file_read` (979-1034). The serial driver and the buffer helpers are
  not part of the port.
- Intended differences (design D4 of change `wintec-file-port`): records with impossible time fields
  are skipped with a warning (the source normalizes them with `mkgmtime`); tracks are named after the
  file (numbered when there are several), waypoints `POI n`.
- Cross-check against the gpsbabel 1.7.0 binary (`-i wbt-tk1`, 2026-11-13) with the synthetic fixture
  `wbt201.tk1`: two tracks with 3 and 2 points and one waypoint in both; positions, altitudes and
  times agree.

## `wbt-bin`

- Source, copyright and license as for `wbt-tk1` (`wbt-200.cc`).
- Intended differences: as for `wbt-tk1`; a file whose size fits no record length ends with an error
  instead of a fatal abort.
- Cross-check against the gpsbabel 1.7.0 binary (`-i wbt-bin`, 2026-11-13) with the synthetic fixture
  `wbt200.bin` (16-byte records): two tracks with 2 and 3 points in both; positions, altitudes and
  times agree.

## `wintec-tes`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `wintec_tes.cc`. Copyright: line 5 "Copyright (C) 2010
  Robert Lipe". License: lines 7-10, GPL-2.0-or-later.
- Translated: `wintec_date_to_time` (lines 40-53) and `wintec_tes_read` (55-90).
- Intended differences: an incomplete last record gives a warning instead of a point made of
  remaining bytes; impossible time fields are skipped with a warning; the track is named after the
  file, waypoints `POI n`.
- Cross-check against the gpsbabel 1.7.0 binary (`-i wintec_tes`, 2026-11-13) with the synthetic
  fixture `wbt202.tes`: 5 track points and one waypoint in both; positions, altitudes and times agree.
- Test fixtures `wbt202.tes`, `wbt200.bin` and `wbt201.tk1` are synthetic (`WintecTestFile`).

## `sbn`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `sbn.cc` (lines 4-5 "Copyright (C) 2008 Rodney
  Lorrimar", "Copyright (C) 2005 Robert Lipe"; lines 7-10 GPL-2.0-or-later) and the packet checksum
  `navilink_checksum_packet` from `navilink.cc` (lines 4-5 "Copyright (C) 2007 Tom Hughes",
  "Copyright (C) 2008 Rodney Lorrimar"; lines 7-10 GPL-2.0-or-later).
- Translated: constants (lines 45-55), `read_packet` (62-118), `read_sbn_header` (169-182),
  `is_sbn_valid`, `decode_sbn_mode`, `decode_sbn_datetime`, `decode_sbn_position`, `decode_sbn_record`
  and `add_logpoints` (184-271); `navilink_checksum_packet` (`navilink.cc` 209-220).
- Intended differences (design D4 of change `locosys-file-port`): a packet with a wrong checksum is
  skipped with a warning and a broken frame ends the file with a warning (the source aborts with
  `fatal`); unknown packet types are skipped silently; the track is named after the file.
- Cross-check against the gpsbabel 1.7.0 binary (`-i sbn`, 2026-11-13) with the synthetic fixture
  `gt31.sbn`: 5 track points in both; positions, altitudes, times (with milliseconds), fix types,
  satellites and HDOP agree.

## `sbp`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `sbp.cc` (copyright and license as `sbn.cc`) and the log
  point decoding from `navilink.cc` (`decode_sbp_msec`, `decode_sbp_datetime_packed`,
  `decode_sbp_position`, `navilink_decode_logpoint`, lines 768-829) with `SBP_RECORD_LEN` from
  `navilink.h` (line 29; lines 4-5 "Copyright (C) 2008 Rodney Lorrimar", "Copyright (C) 2005 Robert
  Lipe"; lines 8-11 GPL-2.0-or-later).
- Translated: `read_sbp_header` (lines 50-82), `read_logpoint` (84-94) and `sbp_read` (96-108).
- Detection (not in the source, which accepts any 64-byte header): the header layout follows the
  comment in `sbp.cc` (lines 53-60, length and `MID_FILE_ID` 0xFD) and `HEADER_SKIP` = 7, the device
  information format the comment in `sbn.cc` (lines 140-148).
- Intended differences: impossible time fields and an incomplete last record give warnings; the track
  is named after the file.
- Cross-check against the gpsbabel 1.7.0 binary (`-i sbp`, 2026-11-13) with the synthetic fixture
  `gt31.sbp`: 5 track points in both; positions, altitudes, times (with milliseconds), satellites and
  HDOP agree.
- Test fixtures `gt31.sbp` and `gt31.sbn` are synthetic (`LocosysTestFile`).

## `gopal`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `gopal.cc`. Copyright: line 4 "Copyright (C) 2008
  Dr. Jürgen Neumann" (Latin-1 in the source), line 5 "Copyright (C) 2005 Robert Lipe … (based on
  nmea.c)". License: lines 8-11, GPL-2.0-or-later.
- Translated: format description (lines 35-41), `gopal_check_line` (85-96), the file name rule of
  `gopal_rd_init` (139-155) and `gopal_read` (165-331) with the defaults `maxspeed` = 200,
  `minspeed` = 0 and `clean` = 1. The great-circle distance is an own haversine helper.
- Intended differences (design D4 of change `gopal-port`): the date is taken from the file name for
  9-field lines (the source has this commented out and uses 1970-01-01) and the day advances at
  midnight (a ToDo of the source); speeds are converted from km/h to m/s (the source stores the km/h
  value as m/s); the result is a track without waypoints (the source creates a route and a waypoint
  per point); the reference point of the jump filter must have a usable position (otherwise the
  source drops every following point); lines are decoded one by one for quick cancellation.
- Cross-check against the gpsbabel 1.7.0 binary (`-i gopal`, 2026-11-13) with the synthetic fixture
  `track20261102_080000.trk` (12-field lines with a jump and a 0/0 line): 5 points in both (gpsbabel:
  route points and waypoints); positions, altitudes and times with milliseconds agree.
- Test fixture `track20261102_080000.trk` is synthetic.

## `magellan`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, files `magproto.cc` (copyright lines 4-5 "Copyright (C) 2002,
  2003, 2004, 2005, 2006, 2007, 2008, 2010 Robert Lipe", license lines 7-10, GPL-2.0-or-later) and
  `magellan.h` (copyright line 2 "Copyright (C) 2002-2005 Robert Lipe", license lines 4-7,
  GPL-2.0-or-later). Shared helper: `ddmm2degrees` (`util.cc`, lines 987-992).
- Translated: `meridian_model` (magellan.h), `pid_to_model` (magproto.cc lines 214-236), `mag_checksum` and
  `mag_pchecksum` (293-312), the sentence handling of `mag_readmsg` (435-575), `mag_dequote` (630-659),
  `parse_istring` (946-964), `mag_trkparse` (972-1027), `mag_wptparse` (1199-1246) and the file part of
  `mag_rd_init_common` and `mag_read` (781-832, 1249-1330) without routes. Icon tables and name shortening
  are only used for writing or icon descriptions and are not part of the port.
- `magellan` and `magellanx` read files the same way (the source differs only when writing), so one format
  covers both.
- Intended differences (design D4/D5 of change `magellan-port`): lines without `$` are skipped with a warning
  (the source stops); empty lines are skipped; a wrong checksum gives a warning (the source ignores it); the
  file ends at `$PMGNCMD,END`; the track name drops only the last extension (the source cuts at the first
  dot); waypoint sentences count only in `.upt` files, as the source's `extension_hint` does with `-t -w`.
- Cross-check against the gpsbabel 1.7.0 binary (`-t -w -i magellan` and `-i magellanx`, 2026-11-13) with the
  fixtures: both formats give identical output; `track01.log` 50 track points and no waypoint, `poi.upt` 3
  waypoints, with identical positions (1e-7 degrees), altitudes, times, names and comments. The only
  difference is in gpsbabel's GPX writer, which writes the name as comment when the comment is empty.
- Test fixtures `track01.log` and `poi.upt` are synthetic.

## `alantrl`

- Source: GPSBabel, tag `gpsbabel_1_7_0`, file `alan.cc`. Copyright: line 8 "Copyright (C) 2007 Gunar Megger",
  line 9 "Copyright (C) 2002-2014 Robert Lipe". License: lines 11-14, GPL-2.0-or-later.
- Translated: the structures `trkhdr`, `loghdr`, `trklog` and `trldata` (lines 107-141), `TRL_HDR_ID` (145),
  the scales (165-175) and `trl_read` (584-644). The byte swapping (206-243, 342-421) is not needed because
  the file is read as little endian independent of the host. Waypoints and routes (`alanwpr`) and writing
  are not part of the port.
- Intended differences (design D3 of change `alan-port`): more than 2500 points per header are limited to
  2500 with a warning (the source reads beyond the track log); empty tracks are dropped; the track comment
  is not kept (the model has no track description); a track without name is named after the file.
- Detection (design D4): the header ID lies at 0x40000, outside the detection prefix, so the format matches
  when all 512 coordinate pairs of the first 4096 bytes are plausible; it is the last format of the catalog.
- Cross-check against the gpsbabel 1.7.0 binary (`-t -i alantrl`, 2026-11-13) with the synthetic fixture
  `map500.trl` (tracks in slots 1 and 6, south/east and north/west): 2 tracks with 120 and 80 points in
  both, identical names, positions (1e-7 degrees), altitudes and speeds; no times in either.
- Test fixture `map500.trl` is synthetic.

## Device protocol `skytraq` (change `skytraq-device-port`)

Not a file format; listed here because it is ported code.

- Source: GPSBabel `skytraq.cc` (tag `gpsbabel_1_7_0`), copyright and license as for `skytraq-bin`.
- Translated: constants (lines 35-52), message layer and baud rate (`skytraq_calc_checksum` to
  `skytraq_set_baud`, 279-494), `skytraq_get_log_buffer_status` (533-578), sector reading and
  `skytraq_read_tracks` (929-1196), `skytraq_probe` (1198-1271), `skytraq_erase` (1273-1285) and
  `skytraq_read` (1335-1366). The serial helpers are replaced by `DeviceConnection`.
- Differences: a timeout while waiting for an acknowledgement counts as "no answer" (retry or next baud
  rate) instead of counting read errors until `fatal`; errors become protocol errors.
- Cross-check (2026-11-13): a simulated logger on a pseudo terminal (Python, scratch directory) was read
  by the gpsbabel 1.7.0 binary (`-i skytraq,baud=0`) and by the app (`-DebugReadDevice skytraq.venus`);
  both got 517 track points with identical positions (1e-7 degrees), altitudes (0.01 m) and times.

## Device protocol `mtk` / `m241` (change `mtk-device-port`)

- Source: GPSBabel `mtk_logger.cc` (tag `gpsbabel_1_7_0`), copyright and license as for `mtk-bin`.
- Translated: command constants (lines 247-251), `do_send_cmd`/`do_cmd` (315-424), `mtk_rd_init`
  (426-480), `mtk_rd_deinit` (482-495), `mtk_erase` (497-532) and `mtk_read` (534-802) without the
  `data.bin` cache and the CSV output.
- Differences: `$PMTK001` acknowledgements are evaluated by their result field (the source reads the
  sub-command field and therefore treats e.g. `$PMTK001,182,2,3` as a failure, losing the log status, so
  it does not re-enable logging); stale answer lines are discarded; the dump is decoded by the `mtk-bin`
  decoder, which also reads the last records that the source drops (see `mtk-bin`).
- Cross-check (2026-11-13): a simulated logger on a pseudo terminal (Python) was read by the gpsbabel 1.7.0
  binary (`-i m241`) and by the app (`-DebugReadDevice m241.holux-m-241`) with the same command sequence
  (plus `$PMTK182,4` re-enabling logging in the app) and the same 4 track points and waypoint.

## Device protocol `wbt` (change `wintec-device-port`)

- Source: GPSBabel `wbt-200.cc` (tag `gpsbabel_1_7_0`), copyright and license as for `wbt-bin`.
- Translated: `rd_drain` to `guess_device` (lines 266-388), `do_cmd`, `do_simple`, `get_param*` (450-500),
  `wbt200_data_read` (697-778), `wbt201_read_chunk`, `wbt201_data_read` (852-977) and `data_read`
  (1036-1054). The chunk checksum is the XOR of the bytes, as `buf_update_checksum`.
- Differences: erasing is a separate operation (the device type is detected again); names as for the files.
- Cross-check (2026-11-13): simulated WBT-201 and WBT-200 loggers on a pseudo terminal (Python) were read by
  the gpsbabel 1.7.0 binary (`-i wbt`) and, for the WBT-201, by the app (`-DebugReadDevice wbt.wintec-wbt-201`)
  with the same command sequence; both got two tracks with 200 and 100 points and one waypoint, with
  identical positions, altitudes and times.

## Device protocol `navilink` (change `navilink-device-port`)

- Source: GPSBabel `navilink.cc` (tag `gpsbabel_1_7_0`), copyright and license as for `sbn`.
- Translated: constants (lines 56-89), `write_packet`, `read_word`, `read_packet` (243-345), the decoders
  (346-443), `serial_read_waypoints` (466-518) without route IDs, `serial_read_track` (541-582) and the
  serial part of `navilink_common_init` (1054-1072). Writing, deleting, routes and the datalog are not part
  of the port.
- Difference: the device information is queried once (the source queries it for waypoints and track).
- Cross-check (2026-11-13): a simulated NaviGPS on a pseudo terminal (Python) was read by the gpsbabel 1.7.0
  binary (`-i navilink`) and by the app (`-DebugReadDevice navilink.locosys-gt-31`); both got 40 waypoints
  and 600 track points with identical positions, altitudes and times.

## Device protocol `magellan` (change `magellan-port`)

- Source: GPSBabel `magproto.cc` (tag `gpsbabel_1_7_0`), copyright and license as for the format `magellan`.
- Translated: `mag_writemsg` without the acknowledgement path (lines 315-346), `mag_handoff` (383-389),
  `mag_verparse` (392-430), `mag_readmsg` (435-575), `terminit`/`termread` (580-616), the reading part of
  `mag_serial_init_common` (731-779, without `nukewpt`) and the serial part of `mag_read` (1249-1330, without
  routes), 4800 baud (option `baud`, line 702). As in the source when reading (`suppress_ack`), no
  acknowledgements are exchanged.
- Differences (design D3/D4): lines without `$` are skipped (the source stops with "line doesn't start with
  '$'", e.g. on the rest of an NMEA sentence after opening the port); the input is discarded before `VERSION`
  and before `TRACK,2`; `$PMGNCMD,UNABLE` is reported as a step instead of a warning; the track is named
  "Magellan" (the source uses the port name, e.g. "cu"); `HANDOFF` is also sent after an error.
- Cross-check (2026-11-13): a simulated Meridian on a pseudo terminal (Python) was read by the gpsbabel 1.7.0
  binary (`-t -w -i magellan`, without the NMEA fragment, on which gpsbabel stops) and by the app
  (`-DebugReadDevice magellan.meridian`, with the fragment) with the same command sequence (`HANDOFF`,
  `VERSION`, `NMEAOFF`, `TRACK,2`, `WAYPOINT`, `HANDOFF`); both got 500 track points and 20 waypoints with
  identical positions, altitudes, times (hundredths of a second), names and comments.

## Device protocol `itracku` (change `itracku-port`)

- Source: GPSBabel `itracku.cc` (tag `gpsbabel_1_7_0`). Copyright: line 2 "Copyright (C) 2008 Andreas Grimme",
  line 3 "Copyright (C) 2005 Robert Lipe". License: lines 5-8, GPL-2.0-or-later. Shared helpers: the semantics
  of `gbser_read_line`/`gbser_read_wait` and the default of 4800 baud in `gbser_init` (`gbser_posix.cc`, line 155).
- Translated: `itracku_data_record` (lines 56-63), the read command and end marker (76-79),
  `itracku_device_write_string`/`_read_string` (125-140), `itracku_device_update_data_read` (154-183),
  `deg_min_to_deg`, `decode_itracku_time`, `to_waypoint` (215-235, 269-282, 304-314), `init_device` (335-355),
  `itracku_is_valid_data_record` (514-517) and `itracku_device_dump_waypts` (520-536). The file format
  `itracku-bin`, the backup options and the real-time position functions are not part of the port.
- Differences (design D3 of change `itracku-port`): the records become a track (with `-t -w` gpsbabel makes
  waypoints, because the last flag sets the objective); records that arrive in the same read as the end marker
  are decoded (the source drops them); silence of 1 s ends the download with a timeout (the source loops
  forever); NMEA output before the greeting is accepted; a missing or wrong greeting is a protocol error
  "No iTrackU found on this port".
- Cross-check (2026-11-13): a simulated iTrackU on a pseudo terminal (Python, 1000 records in 4 KiB chunks plus
  empty slots, then the end marker) was read by the gpsbabel 1.7.0 binary (`-t -i itracku`) and by the app
  (`-DebugReadDevice itracku.xaiox-itracku`) with the same commands. gpsbabel got 960 points, the app 1000;
  the first 960 agree in position, altitude and time, the last 40 are the records gpsbabel drops.

## Device protocol `igotu` (change `igotu-driver`)

- Sources:
  - the author's own myTracks driver `IGotUGT800.m` (myTracks git history, `3cbc727^`), "Copyright (c) 2013
    Dirk Stichling": GT-800 serial protocol (16-byte commands, 9600 baud), count, model, read, record
    decoding (`createTrackPoints`) and purge (`purgeMemory`);
  - igotu2gpx 0.3.0 by Michael Hofmann, downloaded on 2026-11-13 from
    `https://launchpad.net/igotu2gpx/0.3/0.3.0/+download/igotu2gpx-0.3.0.tar.gz`
    (SHA-256 `247459c690ddd23bffd1f66535c65a8653b2dfe2e68e44c707dc4f68c6c9c481`); license GPL-3.0-or-later
    (`src/igotu/igotucommand.cpp` lines 2-7: "either version 3 of the License, or (at your option) any later
    version"). Used: the USB transport and 8-byte chunking (`HACKING`, `igotucommand.cpp`
    `sendCommand`/`sendAndReceive`), identification, model and count commands (`commands.cpp`), the download
    loop and the USB purge with model-specific block counts (`igotucontrol.cpp`, `purge`).
- Differences: milliseconds are kept; waypoints also become waypoints named `POI n`; erasing is offered as
  experimental (undocumented commands, no test hardware).
- Verification (2026-11-13): simulated devices in the tests (serial and HID); the app read a simulated
  GT-800 on a pseudo terminal (`-DebugReadDevice igotu.gt-800`): 150 points, one waypoint. No gpsbabel
  counterpart exists; the USB HID transport is untested without hardware.
