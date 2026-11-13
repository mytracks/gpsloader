# Delta für logger-kit

## MODIFIED Requirements

### Requirement: Formatkatalog
Das Paket SHALL einen Katalog aller unterstützten Dateiformate bereitstellen. Jedes Format SHALL eine feste Kennung, einen lokalisierten Namen und die typischen Dateiendungen haben.

#### Scenario: Katalog abfragen
- **WHEN** eine App den Katalog abfragt
- **THEN** enthält er mindestens die Formate NMEA 0183 (Kennung `nmea`), GPX (Kennung `gpx`) und IGC (Kennung `igc`) mit ihren Dateiendungen
