# Spec Delta

## MODIFIED Requirements

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
