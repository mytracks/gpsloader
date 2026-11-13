# tcx-import Specification

## Purpose
Liest Dateien im Garmin Training Center XML (TCX, Version 2) ein, wie sie Sportuhren, Garmin Connect und Trainings-Apps exportieren. Aus Aktivitäten und Kursen entstehen Tracks und Wegpunkte, ohne gpsbabel.

## Requirements

### Requirement: Aktivitäten
Jede `Activity` unter `Activities` SHALL einen Track ohne Namen ergeben. Jedes `Track`-Element ihrer Runden (`Lap`) SHALL ein eigenes Segment ergeben, in der Reihenfolge der Datei. Segmente ohne Punkte SHALL entfallen.

#### Scenario: Zwei Runden
- **WHEN** eine Aktivität zwei Runden mit je einem `Track` von 10 Trackpunkten hat
- **THEN** entsteht ein Track mit zwei Segmenten zu je 10 Punkten

#### Scenario: Zwei Aktivitäten
- **WHEN** eine Datei zwei Aktivitäten enthält
- **THEN** entstehen zwei Tracks in der Reihenfolge der Datei

### Requirement: Trackpunkte
Ein `Trackpoint` mit `Position` SHALL einen Punkt ergeben:
- **Position:** `LatitudeDegrees` und `LongitudeDegrees`.
- **Zeit:** `Time` (XML-Schema `dateTime`).
- **Höhe:** `AltitudeMeters`.
- **Geschwindigkeit:** `Speed` aus der Erweiterung `TPX` (ActivityExtension v2) in m/s, falls vorhanden.

Herzfrequenz, Trittfrequenz, Distanz und Rundenwerte SHALL ignoriert werden.

#### Scenario: Punkt mit Geschwindigkeit
- **WHEN** ein `Trackpoint` die Zeit `2026-05-01T08:00:00Z`, die Position 53,55° / 9,99°, die Höhe 12,5 m und die TPX-Geschwindigkeit 3,2 enthält
- **THEN** entsteht ein Punkt mit diesen Werten und der Geschwindigkeit 3,2 m/s

### Requirement: Unvollständige Trackpunkte
Trackpunkte ohne `Position` SHALL ohne Warnung übergangen werden. Eine Position außerhalb des gültigen Bereichs oder eine nicht lesbare Zahl MUST verworfen und als Warnung gezählt werden. Ein Punkt ohne lesbare Zeit SHALL ohne Zeit übernommen und als Warnung gezählt werden.

#### Scenario: Pause ohne Position
- **WHEN** ein `Trackpoint` nur `Time` und `HeartRateBpm` enthält
- **THEN** entsteht daraus kein Punkt und keine Warnung

#### Scenario: Ungültige Breite
- **WHEN** ein `Trackpoint` die Breite 95 hat
- **THEN** wird er verworfen, und eine Warnung zählt ihn

#### Scenario: Fehlende Zeit
- **WHEN** ein `Trackpoint` eine Position, aber kein `Time` hat
- **THEN** entsteht ein Punkt ohne Zeit, und eine Warnung zählt die Punkte ohne Datum

### Requirement: Kurse
Jeder `Course` unter `Courses` SHALL einen Track mit dem Namen aus `Name` ergeben, mit einem Segment je `Track`. Jeder `CoursePoint` SHALL einen Wegpunkt ergeben. Er bekommt `Name`, `Time` und `AltitudeMeters`, falls vorhanden, und `Notes` als Kommentar.

#### Scenario: Kurs mit Kurspunkten
- **WHEN** eine Datei einen Kurs „Elbe“ mit 50 Trackpunkten und zwei Kurspunkten enthält
- **THEN** enthält die Aufzeichnung einen Track „Elbe“ mit 50 Punkten und zwei Wegpunkten

### Requirement: Nicht ausgewertete Inhalte
Der Import SHALL `MultiSportSession`, `Workouts`, `Folders`, `Author` und unbekannte Erweiterungen ohne Warnung übergehen.

#### Scenario: Workout
- **WHEN** eine Datei neben einer Aktivität ein Workout enthält
- **THEN** entsteht nur der Track der Aktivität, ohne Warnung

### Requirement: Fehler
Eine Datei, die kein wohlgeformtes XML ist, MUST zu einem Fehler mit Datei und Zeile führen.

#### Scenario: Abgeschnittene Datei
- **WHEN** eine TCX-Datei mitten in einem `Trackpoint` endet
- **THEN** endet das Einlesen mit einem Fehler, der Datei und Zeile nennt

### Requirement: Erkennung
Eine Datei SHALL als TCX erkannt werden, wenn ihr erstes Element `TrainingCenterDatabase` ist, mit oder ohne Namensraum-Präfix. Die Dateiendung `.tcx` SHALL nur als Hinweis dienen.

#### Scenario: TCX mit Endung .xml
- **WHEN** eine TCX-Datei die Endung `.xml` hat
- **THEN** schlägt die Erkennung TCX vor und nicht GPX

#### Scenario: GPX bleibt GPX
- **WHEN** eine GPX-Datei die Endung `.tcx` hat
- **THEN** schlägt die Erkennung GPX vor
