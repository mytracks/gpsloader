# gopal-import Specification

## Purpose
Liest die Tracklogs (`.trk`) von Medion-GoPal-Navigationsgeräten, portiert aus gpsbabel 1.7.0. Daraus entsteht ein Track; das Datum stammt aus dem Dateinamen, fehlerhafte Punkte werden verworfen.

## Requirements

### Requirement: GoPal-Zeilen
Das Format `gopal` SHALL Zeilen mit 9 oder 12 durch Komma getrennten Feldern lesen; andere Zeilen SHALL es ohne Warnung übergehen. Die Felder SHALL sein: Zeitzähler in Mikrosekunden, Zeit `hhmmss` (UTC), Länge, Breite, Höhe (m), Geschwindigkeit (km/h), Fix-Art (0 ergibt `none`, 2 ergibt `2d`), HDOP, Satelliten und bei 12 Feldern zusätzlich das Datum `JJJJMMTT`. Die Millisekunden der Zeit SHALL aus dem Zeitzähler folgen (Mikrosekunden modulo 1 000 000, gerundet auf Millisekunden).

#### Scenario: Zeile mit Datum
- **WHEN** eine Zeile `3801444, 080558, 8.0, 50.0, 295.28, 36.0, 2, 2.9, 3, 20261102, 0, 0` lautet
- **THEN** entsteht ein Punkt bei 50,0° Nord und 8,0° Ost mit der Zeit 2026-11-02T08:05:58.801Z, der Höhe 295,28 m, der Geschwindigkeit 10 m/s, der Fix-Art `2d`, HDOP 2,9 und 3 Satelliten

### Requirement: Datum aus dem Dateinamen
Haben die Zeilen kein Datum, SHALL der Import es aus dem Dateinamen `trackJJJJMMTT_hhmmss.trk` oder `A_JJJJMMTT_hhmmss.trk` übernehmen und bei einer Zeit, die kleiner als die vorherige ist, einen Tag weiterzählen. Ohne Datum im Dateinamen SHALL er die Punkte ohne Zeit übernehmen und eine Warnung erzeugen.

#### Scenario: Datum im Dateinamen
- **WHEN** die Datei `track20261102_093000.trk` Zeilen mit 9 Feldern und der Zeit `083000` enthält
- **THEN** haben die Punkte das Datum 2. November 2026

#### Scenario: Über Mitternacht
- **WHEN** auf eine Zeile mit `235959` eine mit `000001` folgt
- **THEN** liegt der zweite Punkt am folgenden Tag

#### Scenario: Kein Datum
- **WHEN** die Datei `log.trk` Zeilen mit 9 Feldern enthält
- **THEN** haben die Punkte keine Zeit, und eine Warnung nennt ihre Anzahl

### Requirement: Fehlerhafte Punkte
Der Import SHALL Punkte verwerfen, deren Länge oder Breite 0 ist oder außerhalb des gültigen Bereichs liegt, sowie Punkte, die vom letzten übernommenen Punkt aus schneller als 200 km/h erreicht würden (Großkreisentfernung durch Zeitabstand in Sekunden). Bezugspunkt der ersten Prüfung SHALL der erste Punkt mit Fix und gültiger Position sein. Verworfene Punkte SHALL ohne Warnung entfallen, wie in der Vorlage.

#### Scenario: Sprung in den Daten
- **WHEN** zwischen zwei Punkten im Abstand von 1 s ein Punkt 100 km entfernt liegt
- **THEN** entfällt dieser Punkt, und die beiden anderen bleiben erhalten

### Requirement: GoPal-Track
Jede Datei SHALL einen Track ergeben, der nach der Datei ohne Endung heißt. Wegpunkte SHALL nicht entstehen.

#### Scenario: Track statt Route
- **WHEN** eine GoPal-Datei mit drei gültigen Zeilen gelesen wird
- **THEN** enthält die Aufzeichnung einen Track mit drei Punkten und keine Wegpunkte

### Requirement: Erkennung von GoPal
Die Formaterkennung SHALL eine GoPal-Datei daran erkennen, dass die erste nicht leere Zeile und mehr als die Hälfte der ersten fünf nicht leeren Zeilen GoPal-Zeilen sind: 9 oder 12 Felder, das erste eine ganze Zahl, das zweite eine Zeit `hhmmss`, Länge und Breite Zahlen.

#### Scenario: GoPal-Datei
- **WHEN** eine `.trk`-Datei mit GoPal-Zeilen geprüft wird
- **THEN** schlägt die Erkennung `gopal` vor

#### Scenario: Andere CSV-Datei
- **WHEN** eine V-900- oder iBlue-CSV-Datei geprüft wird
- **THEN** schlägt die Erkennung nicht `gopal` vor
