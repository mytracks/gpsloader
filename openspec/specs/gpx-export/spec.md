# gpx-export Specification

## Purpose
Erzeugt aus den ausgelesenen Daten (Tracks, Segmente, Wegpunkte) standardkonforme GPX-1.1-Dateien, die myTracks und andere Programme ohne Anpassungen importieren können.

## Requirements

### Requirement: GPX-1.1-Konformität
Erzeugte Dateien MUST gültiges GPX 1.1 nach dem Schema `http://www.topografix.com/GPX/1/1` in UTF-8 sein. Das `creator`-Attribut SHALL „myTracks Loader“ und die App-Version enthalten, etwa „myTracks Loader 0.1.0“. Erweiterungen, insbesondere die von myTracks, SHALL die Datei nicht enthalten.

#### Scenario: Validierung gegen das Schema
- **WHEN** eine erzeugte Datei gegen das GPX-1.1-XSD geprüft wird
- **THEN** ist sie gültig

#### Scenario: Keine Erweiterungen
- **WHEN** eine Datei erzeugt wird
- **THEN** enthält sie kein `extensions`-Element

#### Scenario: Creator
- **WHEN** die App in Version 0.1.0 eine Datei erzeugt
- **THEN** lautet ihr `creator`-Attribut „myTracks Loader 0.1.0“

### Requirement: Inhalt
Jeder Track SHALL als `trk` mit Namen und einem oder mehreren `trkseg` ausgegeben werden. Jeder Punkt erscheint als `trkpt` mit Breite und Länge, sofern vorhanden mit Höhe (`ele`) und Zeit (`time`). Wegpunkte SHALL als `wpt` ausgegeben werden. Vorhandene Qualitätsangaben SHALL in der Reihenfolge des GPX-1.1-Schemas als `fix`, `sat`, `hdop`, `vdop` und `pdop` erscheinen. Geschwindigkeit und Kurs SHALL nicht ausgegeben werden.

#### Scenario: Track mit Segmenten
- **WHEN** ein Track mit zwei Segmenten zu je 3 Punkten exportiert wird
- **THEN** enthält die Datei ein `trk` mit zwei `trkseg` zu je drei `trkpt`

#### Scenario: Punkt ohne Höhe
- **WHEN** ein Punkt keine Höhe hat
- **THEN** enthält sein `trkpt` kein `ele`-Element

#### Scenario: Wegpunkt
- **WHEN** ein Wegpunkt mit Namen „WPT“ exportiert wird
- **THEN** enthält die Datei ein `wpt` mit `name` „WPT“

#### Scenario: Punkt mit Qualitätsangaben
- **WHEN** ein Punkt einen 3D-Fix, 8 Satelliten und HDOP 0,9 hat
- **THEN** enthält sein `trkpt` `<fix>3d</fix>`, `<sat>8</sat>` und `<hdop>0.9</hdop>` in dieser Reihenfolge, und die Datei bleibt gültig nach dem GPX-1.1-XSD

#### Scenario: Geschwindigkeit wird nicht ausgegeben
- **WHEN** ein Punkt eine Geschwindigkeit hat
- **THEN** enthält die Datei weder ein `speed`-Element noch eine Erweiterung dafür

### Requirement: Zeiten in UTC
Zeitangaben MUST als ISO 8601 in UTC mit dem Suffix `Z` ausgegeben werden. Bruchteile von Sekunden SHALL nur erscheinen, wenn sie ungleich null sind.

#### Scenario: Ganze Sekunden
- **WHEN** ein Punkt die Zeit 2. November 2026, 14:30:05 UTC hat
- **THEN** lautet `time` `2026-11-02T14:30:05Z`

#### Scenario: Millisekunden
- **WHEN** ein Punkt die Zeit 14:30:05,250 UTC hat
- **THEN** lautet `time` `2026-11-02T14:30:05.250Z`

### Requirement: Gebietsschema-unabhängige Zahlen
Koordinaten und Höhen MUST mit Punkt als Dezimaltrennzeichen und ohne Tausendertrennzeichen ausgegeben werden, unabhängig von der Systemsprache. Koordinaten SHALL bis zu 7 Nachkommastellen haben, ohne nachgestellte Nullen.

#### Scenario: Deutsches Gebietsschema
- **WHEN** das System auf Deutsch eingestellt ist und ein Punkt die Breite 51,7411580 hat
- **THEN** lautet das Attribut `lat="51.741158"`

### Requirement: Sonderzeichen in Texten
Namen und Beschreibungen MUST korrekt für XML maskiert werden.

#### Scenario: Name mit Sonderzeichen
- **WHEN** ein Track „Berg & Tal <1>“ heißt
- **THEN** ist die Datei wohlgeformt und der Name wird beim Einlesen unverändert als „Berg & Tal <1>“ gelesen

### Requirement: Deterministische Ausgabe
Gleiche Eingabedaten MUST byte-identische Dateien ergeben, mit Ausnahme des Erzeugungszeitpunkts in `metadata/time`.

#### Scenario: Zweimal exportieren
- **WHEN** dieselben Daten zweimal mit festem Erzeugungszeitpunkt exportiert werden
- **THEN** sind beide Dateien byte-identisch

### Requirement: Sicheres Schreiben
Die Datei MUST atomar geschrieben werden. Schlägt das Schreiben fehl, SHALL keine unvollständige Datei am Zielort zurückbleiben, und eine bestehende Datei mit gleichem Namen MUST unverändert bleiben.

#### Scenario: Ziel nicht beschreibbar
- **WHEN** der Zielordner schreibgeschützt ist
- **THEN** wird ein Schreibfehler gemeldet, und am Zielort entsteht keine Datei
