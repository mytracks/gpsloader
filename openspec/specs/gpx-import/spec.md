# gpx-import Specification

## Purpose
Liest GPX-Dateien ein, wie sie Garmin-Geräte und andere Logger auf ihrem Speicher ablegen. Tracks und Wegpunkte gelangen so ins gemeinsame Datenmodell und lassen sich normalisiert wieder als GPX 1.1 ausgeben.

## Requirements

### Requirement: GPX-Versionen
Der Import SHALL GPX 1.0 (`http://www.topografix.com/GPX/1/0`) und GPX 1.1 (`http://www.topografix.com/GPX/1/1`) lesen. Dateien ohne oder mit unbekanntem Namensraum SHALL er lesen, solange das Wurzelelement `gpx` heißt.

#### Scenario: GPX 1.0 eines älteren Garmin-Geräts
- **WHEN** eine GPX-1.0-Datei mit einem Track eingelesen wird
- **THEN** enthält die Aufzeichnung diesen Track mit allen Punkten

#### Scenario: Ohne Namensraum
- **WHEN** das Wurzelelement `<gpx>` keinen Namensraum hat
- **THEN** wird die Datei trotzdem eingelesen

### Requirement: Tracks und Wegpunkte
Jedes `trk` SHALL mit seinem Namen als Track übernommen werden, jedes `trkseg` als Segment. Jedes `wpt` SHALL als Wegpunkt mit Name und Kommentar übernommen werden. Routen (`rte`) SHALL der Import nicht übernehmen.

#### Scenario: Garmin-Datei mit Tracks, Wegpunkten und Route
- **WHEN** eine Datei zwei Tracks, fünf Wegpunkte und eine Route enthält
- **THEN** enthält die Aufzeichnung zwei Tracks und fünf Wegpunkte, aber keine Route

### Requirement: Punktangaben
Der Import SHALL für jeden Punkt folgende Angaben übernehmen, soweit vorhanden: `lat`, `lon`, `ele`, `time`, `sat`, `hdop`, `vdop`, `pdop` und `fix`. Bei GPX 1.0 SHALL er zusätzlich `speed` und `course` übernehmen. Erweiterungen (`extensions`) und unbekannte Elemente SHALL er ohne Warnung ignorieren.

#### Scenario: Garmin-Erweiterungen
- **WHEN** Trackpunkte `gpxtpx:TrackPointExtension` mit Puls enthalten
- **THEN** werden die Punkte ohne diese Angaben und ohne Warnung übernommen

### Requirement: Zeitangaben
Zeiten SHALL nach ISO 8601 mit Zeitzonenangabe gelesen werden, also `Z` oder `±hh:mm`, mit oder ohne Bruchteil von Sekunden. Daraus entsteht ein absoluter Zeitpunkt. Zeiten ohne Zonenangabe SHALL als UTC gelten.

#### Scenario: Zeit mit Zonenversatz
- **WHEN** ein Punkt die Zeit `2026-11-02T15:30:05+01:00` hat
- **THEN** ist sein Zeitpunkt 2. November 2026, 14:30:05 UTC

### Requirement: Ungültige Punkte
Punkte ohne oder mit nicht lesbarer Breite oder Länge, mit Breite außerhalb von ±90° oder mit Länge außerhalb von ±180° MUST übersprungen und als Warnung gezählt werden.

#### Scenario: Punkt außerhalb des Wertebereichs
- **WHEN** ein `trkpt` die Breite 123.4 hat
- **THEN** fehlt dieser Punkt in der Aufzeichnung, und eine Warnung zählt ihn

### Requirement: Nicht wohlgeformte Dateien
Ist eine Datei kein wohlgeformtes XML, MUST der Import mit einem Fehler enden, der Datei und Zeile nennt. Bis dahin gelesene Punkte SHALL er nicht als Teilergebnis zurückgeben.

#### Scenario: Abgeschnittene Datei
- **WHEN** eine GPX-Datei mitten in einem `trkpt` endet
- **THEN** endet der Import mit einem Fehler, der Datei und Zeile nennt

### Requirement: Erkennung
Die Formaterkennung SHALL eine Datei als GPX erkennen, wenn ihr erstes Element `gpx` heißt.

#### Scenario: GPX mit Endung `.xml`
- **WHEN** eine GPX-Datei die Endung `.xml` hat
- **THEN** schlägt die Erkennung GPX vor
