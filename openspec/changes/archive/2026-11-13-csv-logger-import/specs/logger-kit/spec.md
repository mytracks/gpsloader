# Delta für logger-kit

## MODIFIED Requirements

### Requirement: Formatkatalog
Das Paket SHALL einen Katalog aller unterstützten Dateiformate bereitstellen. Jedes Format SHALL eine feste Kennung, einen lokalisierten Namen und die typischen Dateiendungen haben.

#### Scenario: Katalog abfragen
- **WHEN** eine App den Katalog abfragt
- **THEN** enthält er mindestens diese Formate mit ihren Dateiendungen:
  - NMEA 0183 (Kennung `nmea`)
  - GPX (Kennung `gpx`)
  - IGC (Kennung `igc`)
  - Garmin FIT (Kennung `fit`)
  - TCX (Kennung `tcx`)
  - Suunto SML (Kennung `suunto-sml`)
  - KML und KMZ (Kennung `kml`, Endungen `kml` und `kmz`)
  - Columbus V-900 (Kennung `v900`, Endung `csv`)
  - iBlue-CSV (Kennung `iblue-csv`, Endung `csv`)
