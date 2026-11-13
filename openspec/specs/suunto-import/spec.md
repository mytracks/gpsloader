# suunto-import Specification

## Purpose
Liest Aufzeichnungen der Suunto-Ambit-Uhren im SML-Format ein, wie sie Moveslink und Movescount als `.sml` oder `.xml` speichern. Daraus entstehen Tracks, ohne gpsbabel und ohne Python.

## Requirements

### Requirement: Proben
Der Import SHALL die Elemente `Sample` unter `sml/DeviceLog/Samples` lesen. Jede Probe mit `Latitude` und `Longitude` SHALL einen Trackpunkt ergeben, unabhängig von ihrem `SampleType`, etwa `gps-base` oder `gps-small`. Proben ohne Position SHALL keine Punkte ergeben.

#### Scenario: Periodische Probe
- **WHEN** eine Probe vom Typ `periodic` nur Höhe, Temperatur und Luftdruck enthält
- **THEN** entsteht daraus kein Punkt

### Requirement: Werte der Punkte
Der Import SHALL folgende Werte übernehmen:
- **Position:** `Latitude` und `Longitude` im Bogenmaß, umgerechnet in Grad.
- **Zeit:** `UTC` (XML-Schema `dateTime`).
- **Bewegung:** `GPSSpeed` in m/s und `GPSHeading` im Bogenmaß, umgerechnet in Grad.
- **Qualität:** `GpsHDOP` als HDOP, `NumberOfSatellites` als Satellitenzahl.

#### Scenario: GPS-Probe umrechnen
- **WHEN** eine Probe `Latitude` 0.8726646259971648, `Longitude` 0.17453292519943295, `UTC` `2026-05-01T08:00:00Z`, `GPSHeading` 3.141592653589793 und `NumberOfSatellites` 12 enthält
- **THEN** entsteht ein Punkt bei 50° Nord und 10° Ost, mit dieser Zeit, dem Kurs 180° und 12 Satelliten

### Requirement: Fehlerhafte Proben
Eine Position außerhalb des gültigen Bereichs oder eine nicht lesbare Zahl MUST verworfen und als Warnung gezählt werden. Fehlt eine lesbare `UTC`-Zeit, SHALL der Punkt ohne Zeit übernommen und als Warnung gezählt werden.

#### Scenario: Ungültige Breite
- **WHEN** eine Probe die `Latitude` 2.0 hat (mehr als π/2)
- **THEN** wird sie verworfen, und eine Warnung zählt sie

### Requirement: Höhe
Liegt die letzte periodische Probe mit `Altitude` höchstens 60 Sekunden (nach `UTC`) vor dem Punkt, SHALL ihr Wert als Höhe des Punkts gelten (barometrische Höhe). Mehrere Punkte können dieselbe periodische Probe nutzen. Andernfalls SHALL `GPSAltitude` der Probe verwendet werden, sonst keine Höhe.

#### Scenario: Barometrische Höhe
- **WHEN** einer GPS-Probe mit `GPSAltitude` 130 zehn Sekunden vorher eine periodische Probe mit `Altitude` 118 vorausgeht
- **THEN** hat der Punkt die Höhe 118 m

#### Scenario: Nur GPS-Höhe
- **WHEN** vor einer GPS-Probe mit `GPSAltitude` 130 keine periodische Probe innerhalb von 60 Sekunden liegt
- **THEN** hat der Punkt die Höhe 130 m

### Requirement: Track und Pausen
Jede Datei SHALL einen Track mit dem Dateinamen ohne Endung ergeben. Ein Ereignis `Pause` mit `State` `True` SHALL das laufende Segment beenden. Punkte nach einem `Pause`-Ereignis mit `State` `False` SHALL in ein neues Segment kommen. Segmente ohne Punkte SHALL entfallen.

#### Scenario: Aufzeichnung mit Pause
- **WHEN** eine Datei 20 GPS-Proben enthält, dann eine Pause (`State` `True`), ein Weiter (`State` `False`) und 10 weitere GPS-Proben
- **THEN** hat der Track zwei Segmente mit 20 und 10 Punkten

#### Scenario: Startereignis
- **WHEN** die erste Probe der Datei ein `Pause`-Ereignis mit `State` `False` enthält
- **THEN** entsteht dadurch kein leeres Segment

### Requirement: Fehler
Eine Datei, die kein wohlgeformtes XML ist, MUST zu einem Fehler mit Datei und Zeile führen. Kopfdaten (`Header`, `Device`) SHALL ignoriert werden.

#### Scenario: Abgeschnittene Datei
- **WHEN** eine SML-Datei mitten in einer Probe endet
- **THEN** endet das Einlesen mit einem Fehler, der Datei und Zeile nennt

### Requirement: Erkennung
Eine Datei SHALL als Suunto SML erkannt werden, wenn ihr erstes Element `sml` ist, mit oder ohne Namensraum-Präfix. Die Dateiendungen `.sml` und `.xml` SHALL nur als Hinweis dienen.

#### Scenario: SML mit Endung .xml
- **WHEN** eine SML-Datei die Endung `.xml` hat
- **THEN** schlägt die Erkennung Suunto SML vor und nicht GPX
