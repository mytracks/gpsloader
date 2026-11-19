# Device catalog of the old app (myTracks)

Generated automatically from `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist` (143 entries).
Columns: device name, connection type (`type`), driver (`driver`), additional arguments (`additionalarguments`).
The `driver` value is shortened for shell commands; the originals are in the plist.

## USB (serial) — 50 devices

| Device | Driver | Additional arguments | Driver URL |
|---|---|---|---|
| Maptaq Trip IQ | `*BG728` |  |  |
| Gisteq PhotoTrackr (CD111) | `!bash -c 'cd $TMPDIR; stty 115200 cs8 raw < $DEVICE; sleep 1; "$BUNDLE/Contents/Resources/…` |  |  |
| Gisteq PhotoTrackr Lite (DPL700) | `!bash -c 'cd $TMPDIR; stty 115200 cs8 raw < $DEVICE; sleep 1; "$BUNDLE/Contents/Resources/…` |  |  |
| GOSGET S1 | `!cd $TMPDIR; "$BUNDLE/Contents/Resources/rgm3800-rev25.py" -d $DEVICE trackx 0- > $GPX!DEL…` |  | https://mytracks.zendesk.com/entries/20339333-royaltek-rgm-3800 |
| Holux GPSport 245 - alternative | `!bash -c 'cd $TMPDIR; rm -f $TMPDIRm241.csv; rm -f $TMPDIRdata.bin; "$BUNDLE/Contents/MacO…` |  | http://www.holux.com/JCore/en/support/downloadCenter.jsp |
| MainNav | `!cd $TMPDIR; python "$BUNDLE/Contents/Resources/mainnavdist/mainnav-reader-helper" $DEVICE…` |  |  |
| Royaltek RGM-3800 | `!cd $TMPDIR; "$BUNDLE/Contents/Resources/rgm3800-rev25.py" -d $DEVICE trackx 0- > $GPX!DEL…` |  | https://mytracks.zendesk.com/entries/20339333-royaltek-rgm-3800 |
| XAiOX iTrackU - Nemerix | `!bash -c 'cd $TMPDIR; stty 115200 cs8 raw < $DEVICE; sleep 1; "$BUNDLE/Contents/Resources/…` |  |  |
| XAiOX iTrackU - SIRFIII | `!bash -c 'cd $TMPDIR; stty 115200 cs8 raw < $DEVICE; sleep 1; "$BUNDLE/Contents/Resources/…` |  |  |
| XAiOX iTrackU - gpsbabel | `itracku` |  |  |
| Holux GPSport 245 | `m241` |  | http://www.holux.com/JCore/en/support/downloadCenter.jsp |
| Holux M-241 | `m241` |  | http://www.holux.com/JCore/en/support/downloadCenter.jsp |
| Magellan Meridian | `magellan` |  |  |
| Magellan Meridian Gold | `magellan` |  |  |
| Magellan Meridian Platinum | `magellan` |  |  |
| Magellan SporTrak Map | `magellan` |  |  |
| Magellan SporTrak Map Color | `magellan` |  |  |
| Magellan SporTrak Map Pro | `magellan` |  |  |
| Magellan SporTrak Map Topo | `magellan` |  |  |
| Blumax GPS-4044 | `mtk` |  |  |
| iBlue 747 | `mtk` |  |  |
| iTrek Z1 | `mtk` |  |  |
| Networx iGeo | `mtk` |  |  |
| Photomate 887 | `mtk` |  |  |
| QStarz BT-100 | `mtk` |  |  |
| Qstarz BT-Q1000 | `mtk` |  |  |
| Qstarz BT-Q1300 | `mtk` |  |  |
| Transystem 860E | `mtk` |  |  |
| Locosys BGT-31 | `navilink` |  | http://www.locosystech.com/product.php?zln=en&id=30# |
| Locosys GT-11 | `navilink` |  | http://www.locosystech.com/product.php?zln=en&id=30# |
| Locosys GT-31 | `navilink` |  | http://www.locosystech.com/product.php?zln=en&id=30# |
| NaviGPS | `navilink` |  |  |
| NaviGPS-BT | `navilink` |  |  |
| Navilink - generic | `navilink` |  |  |
| Canmore GT-730FL | `skytraq` | `,initbaud=0` |  |
| Canmore GT-740FL | `skytraq` | `,initbaud=0` |  |
| Canmore GT-750F | `skytraq` | `,initbaud=38400,baud=38400` | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| Conrad GPS-Datenlogger GT-730 | `skytraq` | `,initbaud=38400,baud=38400` | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| Conrad GPS-Datenlogger GT-750 | `skytraq` | `,initbaud=38400,baud=38400` | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| Dörr GPS Photo Logger | `skytraq` | `,initbaud=38400,baud=38400` | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| Gisteq PhotoTrackr mini (DPL900) | `skytraq` | `,baud=38400,initbaud=38400` | https://mytracks.zendesk.com/entries/20339188-gisteq-dpl900 |
| Navin MiniHomer | `skytraq` | `,initbaud=38400` | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| SkyTraq Venus | `skytraq` |  |  |
| Travel Honey | `skytraq` |  |  |
| Ventus GPS Route Logger G730 | `skytraq` | `,initbaud=38400,baud=38400` | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| G-Rays 2 | `wbt` |  |  |
| Wintec WBT-100 | `wbt` |  |  |
| Wintec WBT-200 | `wbt` |  |  |
| Wintec WBT-201 | `wbt` |  |  |
| Wintec WSG-1000 (G-Tender) | `wbt` |  |  |

## Bluetooth (serial/RFCOMM) — 16 devices

| Device | Driver | Additional arguments | Driver URL |
|---|---|---|---|
| GNS 2000 | `*GNS2000` |  | skip |
| MainNav | `!cd $TMPDIR; python "$BUNDLE/Contents/Resources/mainnavdist/mainnav-reader-helper" $DEVICE…` |  |  |
| Royaltek RBT-2300 | `!cd $TMPDIR; "$BUNDLE/Contents/Resources/rgm3800-rev25.py" -d $DEVICE trackx 0- > $GPX!DEL…` |  | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| Royaltek RBT-2300 (alternative) | `!cd $TMPDIR; "$BUNDLE/Contents/Resources/rbt2300.py" -d $DEVICE trackx 0- > $GPX!DEL!cd $T…` |  | http://www.mytracks4mac.com/download/md_PL2303_MacOSX10.zip |
| Holux M-241 | `m241` |  | http://www.holux.com/JCore/en/support/downloadCenter.jsp |
| Blumax GPS-4044 | `mtk` |  |  |
| iBlue 747 | `mtk` |  |  |
| iTrek Z1 | `mtk` |  |  |
| QStarz BT-100 | `mtk` |  |  |
| Qstarz BT-Q1000 | `mtk` |  |  |
| Qstarz BT-Q1300 | `mtk` |  |  |
| G-Rays 2 | `wbt` |  |  |
| Wintec WBT-100 | `wbt` |  |  |
| Wintec WBT-200 | `wbt` |  |  |
| Wintec WBT-201 | `wbt` |  |  |
| Wintec WSG-1000 (G-Tender) | `wbt` |  |  |

## File (USB storage/SD card) — 40 devices

| Device | Driver | Additional arguments | Driver URL |
|---|---|---|---|
| Alan Map500 | `alantrl` |  |  |
| Cetus for Palm/OS | `cetus` |  |  |
| cotoGPS for Palm/OS | `coto` |  |  |
| Canmore G-Porter GP-102+ | `garmin_fit` |  |  |
| Garmin FIT Fileformat | `garmin_fit` |  |  |
| Medion GoPAL | `gopal` |  |  |
| Garmin Colorado 300 | `gpx` |  |  |
| Garmin Colorado 400c | `gpx` |  |  |
| Garmin Colorado 400i | `gpx` |  |  |
| Garmin Colorado 400t | `gpx` |  |  |
| Garmin Dakota | `gpx` |  |  |
| Garmin GPSmap 62 | `gpx` |  |  |
| Garmin Nuvi | `gpx` |  |  |
| Garmin Oregon | `gpx` |  |  |
| Garmin Road Tech Zumo | `gpx` |  |  |
| Garmin StreetPilot | `gpx` |  |  |
| Garmin Zumo | `gpx` |  |  |
| IGC Fileformat | `gpx` | `!"$BUNDLE/Contents/MacOS/gpsbabel" -i igc -f $INPUTFILE i-o …` |  |
| Suunto Ambit/Movescout Fileformat (SML) | `gpx` | `!cd $TMPDIR; cp $INPUTFILE ambit.sml; rm -f ambit.gpx; "$BUN…` |  |
| Suunto Ambit/Movescout Fileformat (XML) | `gpx` | `!cd $TMPDIR; cp $INPUTFILE ambit.xml; rm -f ambit.gpx; "$BUN…` |  |
| TCX Fileformat | `gpx` | `!"$BUNDLE/Contents/MacOS/gpsbabel" -i gtrnctr -f $INPUTFILE …` |  |
| Wintec WSG-2000 NAL Fileformat | `gpx` | `!rm -f $GPX; "$BUNDLE/Contents/MacOS/wsg2000" $INPUTFILE > $…` |  |
| Magellan Explorist | `magellan` |  |  |
| Locosys BGT-31 | `navilink` |  |  |
| Locosys GT-11 | `navilink` |  |  |
| Locosys GT-31 | `navilink` |  |  |
| NaviGPS | `navilink` |  |  |
| NaviGPS-BT | `navilink` |  |  |
| Amaryllo Trip Tracker (SD-Card) | `nmea` |  |  |
| AMOD AGL3080 | `nmea` |  |  |
| ATP Photo Finder | `nmea` |  |  |
| Canon EOS LOG Fileformat | `nmea` |  |  |
| NMEA Fileformat | `nmea` |  |  |
| Sony GPS CS-1 | `nmea` |  |  |
| Sony GPS CS-3 | `nmea` |  |  |
| Locosys/NaviGPS GT-11/BGT-11/T-31/BGT-31 SiRF binary logfile (.sbn) | `sbn` |  |  |
| Locosys/NaviGPS GT-11/BGT-11/GT-31/BGT-31 datalogger (.sbp) | `sbp` |  |  |
| Columbus V-900 (using memory card reader) | `v900` |  |  |
| Visiontac VGPS-900 | `v900` |  |  |
| Wintec WBT-202 (using SD card) | `wintec_tes` |  |  |

## LoadMyTracks (external app) — 37 devices

| Device | Driver | Additional arguments | Driver URL |
|---|---|---|---|
| Garmin - USB generic | `loadmytracks` |  |  |
| Garmin 12XL | `loadmytracks` |  |  |
| Garmin 38 | `loadmytracks` |  |  |
| Garmin 76S | `loadmytracks` |  |  |
| Garmin Colorado | `loadmytracks` |  |  |
| Garmin Edge 205 | `loadmytracks` |  |  |
| Garmin Edge 305 | `loadmytracks` |  |  |
| Garmin Edge 605 | `loadmytracks` |  |  |
| Garmin Edge 705 | `loadmytracks` |  |  |
| Garmin eMap | `loadmytracks` |  |  |
| Garmin eTrex Venture C | `loadmytracks` |  |  |
| Garmin eTrex Vista | `loadmytracks` |  |  |
| Garmin eTrex Vista C | `loadmytracks` |  |  |
| Garmin eTrex Vista Cx | `loadmytracks` |  |  |
| Garmin ForeRunner 201 | `loadmytracks` |  |  |
| Garmin ForeRunner 301 | `loadmytracks` |  |  |
| Garmin ForeRunner 305 | `loadmytracks` |  |  |
| Garmin Foretrex 201 | `loadmytracks` |  |  |
| Garmin Geko 301 | `loadmytracks` |  |  |
| Garmin GPS 60CSx | `loadmytracks` |  |  |
| Garmin GPS III+ | `loadmytracks` |  |  |
| Garmin GPS V | `loadmytracks` |  |  |
| Garmin GPSmap 60Cx | `loadmytracks` |  |  |
| Garmin GPSmap 76Cx | `loadmytracks` |  |  |
| Garmin Legend C | `loadmytracks` |  |  |
| Garmin Quest | `loadmytracks` |  |  |
| Garmin StreetPilot 2620 | `loadmytracks` |  |  |
| Garmin StreetPilot c320 | `loadmytracks` |  |  |
| GlobalSat DG-100 | `loadmytracks` |  |  |
| GlobalSat GH-615 | `loadmytracks` |  |  |
| Lowrance - generic | `loadmytracks` |  |  |
| Magellan - generic | `loadmytracks` |  |  |
| Magellan eXplorist 210 | `loadmytracks` |  |  |
| Magellan Meridian Color | `loadmytracks` |  |  |
| Timex 3rd Generation GPS (TrailRunner BodyLink 3D) | `loadmytracks` |  |  |
| TomTom - generic | `loadmytracks` |  |  |
| TomTom Go 910 | `loadmytracks` |  |  |

## Overview by driver (without LoadMyTracks)

| Driver | Number of entries |
|---|---|
| gpsbabel: gpx | 16 |
| gpsbabel: mtk | 15 |
| Shell command / helper script | 11 |
| gpsbabel: navilink | 11 |
| gpsbabel: skytraq | 11 |
| gpsbabel: wbt | 10 |
| gpsbabel: magellan | 8 |
| gpsbabel: nmea | 7 |
| gpsbabel: m241 | 3 |
| gpsbabel: v900 | 2 |
| gpsbabel: garmin_fit | 2 |
| gpsbabel: gopal | 1 |
| gpsbabel: alantrl | 1 |
| gpsbabel: cetus | 1 |
| gpsbabel: coto | 1 |
| gpsbabel: sbp | 1 |
| gpsbabel: sbn | 1 |
| gpsbabel: itracku | 1 |
| gpsbabel: wintec_tes | 1 |
| Internal driver (BG728) | 1 |
| Internal driver (GNS2000) | 1 |
