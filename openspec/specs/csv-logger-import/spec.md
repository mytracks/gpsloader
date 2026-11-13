# csv-logger-import Specification

## Purpose
Liest die CSV-Dateien der Columbus V-900/Visiontac VGPS-900 und der iBlue-Software, clean-room in GPSLoggerKit. Daraus entstehen Tracks und, aus Markierungen, Wegpunkte.

## Requirements

### Requirement: Zeilen
Der Import SHALL CSV-Dateien zeilenweise lesen und Zeilen mit LF, CRLF oder CR als Ende akzeptieren. Leere Zeilen und Zeilen, die nur aus Füllbytes bestehen, SHALL er ohne Warnung übergehen.

#### Scenario: Leere Zeile am Ende
- **WHEN** eine Datei mit einer Leerzeile oder einer Zeile aus NUL-Bytes endet
- **THEN** entsteht daraus weder ein Punkt noch eine Warnung

### Requirement: Felder
Der Import SHALL die Felder einer Zeile am Komma trennen und jedes Feld von Leerzeichen, Tabulatoren und NUL-Bytes am Anfang und Ende befreien. Ein leeres Feld SHALL als fehlender Wert gelten.

#### Scenario: Felder mit Füllbytes
- **WHEN** ein Feld einer V-900-Datei `100` gefolgt von zwei NUL-Bytes enthält
- **THEN** wird es als `100` gelesen

### Requirement: Kopfzeile
Eine Datei SHALL mit einer Kopfzeile beginnen. Die Spalten SHALL über die Namen dieser Kopfzeile zugeordnet werden, unabhängig von Groß- und Kleinschreibung. Ein leeres Feld nach einem abschließenden Komma SHALL keine eigene Spalte bilden. Fehlt eine Pflichtspalte des Formats, MUST das Lesen mit einem Fehler enden, der die Datei und Zeile 1 nennt.

#### Scenario: Pflichtspalte fehlt
- **WHEN** einer iBlue-CSV-Datei die Spalte `E/W` fehlt
- **THEN** endet das Lesen mit einem Fehler für Zeile 1

### Requirement: Verworfene Zeilen
Eine Datenzeile mit ungültigem oder fehlendem Datum, ungültiger Zeit oder nicht lesbarer Position MUST verworfen und als Warnung gezählt werden, mit der Zeilennummer des ersten Falls. Eine Position außerhalb des gültigen Bereichs MUST verworfen und als ungültige Koordinate gezählt werden. Nicht lesbare Höhen, Geschwindigkeiten, Kurse und DOP-Werte SHALL ohne Warnung als fehlend gelten.

#### Scenario: Unbrauchbare Zeile
- **WHEN** eine Datenzeile weniger Felder hat, als für Datum, Zeit und Position nötig sind
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt den verworfenen Datensatz mit seiner Zeilennummer

#### Scenario: Breite außerhalb des Bereichs
- **WHEN** eine Zeile die Breite 95° hat
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt die ungültige Koordinate

### Requirement: V-900-Spalten
Das Format `v900` SHALL Dateien lesen, deren Kopfzeile mit den Spalten `INDEX`, `TAG`, `DATE`, `TIME`, `LATITUDE N/S` und `LONGITUDE E/W` beginnt. Es SHALL die Spalten des einfachen Modus (`HEIGHT`, `SPEED`, `HEADING`, `VOX`) und des professionellen Modus (zusätzlich `FIX MODE`, `VALID`, `PDOP`, `HDOP`, `VDOP`) auswerten, soweit vorhanden.

#### Scenario: Einfacher Modus
- **WHEN** eine Datei die Kopfzeile `INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT,SPEED,HEADING,VOX` und die Zeile `1,T,261102,120000,50.000000N,008.000000E,100,36,45,` enthält
- **THEN** entsteht ein Punkt bei 50,0° Nord und 8,0° Ost mit der Zeit 2026-11-02T12:00:00Z, der Höhe 100 m, der Geschwindigkeit 10 m/s und dem Kurs 45°

### Requirement: V-900-Zeit und -Position
Das Format `v900` SHALL `DATE` als `JJMMTT` mit den Jahren 2000–2099 und `TIME` als `hhmmss` lesen, zusammen als UTC. Es SHALL `LATITUDE N/S` und `LONGITUDE E/W` als Dezimalgrad mit nachgestelltem `N`, `S`, `E` oder `W` lesen, wobei `S` und `W` den Wert negativ machen. Ein anderer Buchstabe MUST die Zeile verwerfen.

#### Scenario: Südlich und westlich
- **WHEN** eine Zeile die Position `50.000200S` und `008.000100W` hat
- **THEN** sind Breite und Länge negativ

#### Scenario: Ungültige Hemisphäre
- **WHEN** eine Zeile die Breite `50.000000X` hat
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt den verworfenen Datensatz

### Requirement: V-900-Messwerte
Das Format `v900` SHALL `HEIGHT` als Höhe in Metern, `SPEED` in km/h und `HEADING` als Kurs in Grad lesen. Im professionellen Modus SHALL `VALID` = `DGPS` die Fix-Art `dgps` ergeben, sonst `FIX MODE` = `2D` bzw. `3D` die Fix-Art `2d` bzw. `3d`. `PDOP`, `HDOP` und `VDOP` SHALL übernommen werden, wenn sie größer als 0 sind.

#### Scenario: Professioneller Modus
- **WHEN** eine Datei zusätzlich die Spalten `FIX MODE`, `VALID`, `PDOP`, `HDOP` und `VDOP` hat und eine Zeile die Werte `3D`, `SPS`, `2.1`, `1.2` und `1.8` enthält
- **THEN** hat der Punkt die Fix-Art `3d`, PDOP 2,1, HDOP 1,2 und VDOP 1,8

#### Scenario: Differentielles GPS
- **WHEN** eine Zeile im professionellen Modus `VALID` = `DGPS` hat
- **THEN** hat der Punkt die Fix-Art `dgps`

#### Scenario: Negative Höhe
- **WHEN** das Feld `HEIGHT` den Wert `-5` hat
- **THEN** hat der Punkt die Höhe -5 m

### Requirement: V-900-Markierungen
Jede gültige Zeile einer V-900-Datei SHALL einen Trackpunkt ergeben. Hat `TAG` den Wert `C` oder `D` (Markierung per Taste), SHALL zusätzlich ein Wegpunkt mit Position, Zeit und Höhe des Punkts entstehen, der `POI` gefolgt von der laufenden Nummer der Markierung in der Datei heißt. Bei `TAG` = `V` (Sprachaufnahme) SHALL der Wegpunkt wie die Aufnahme heißen, also wie der Wert aus `VOX` mit der Endung `.WAV`. Ist `VOX` leer, SHALL er wie eine Markierung per Taste heißen.

#### Scenario: Markierung per Taste
- **WHEN** die zweite Markierung einer Datei eine Zeile mit `TAG` = `C` ist
- **THEN** entstehen ein Trackpunkt und ein Wegpunkt namens `POI 2` an derselben Position

#### Scenario: Sprachaufnahme
- **WHEN** eine Zeile `TAG` = `V` und `VOX` = `VOX00003` hat
- **THEN** entsteht neben dem Trackpunkt ein Wegpunkt namens `VOX00003.WAV`

### Requirement: iBlue-Spalten
Das Format `iblue-csv` SHALL Dateien lesen, deren Kopfzeile mit `INDEX` beginnt und die Spalten `DATE`, `TIME`, `LATITUDE`, `N/S`, `LONGITUDE` und `E/W` enthält, in beliebiger Reihenfolge. Es SHALL außerdem `VALID`, `HEIGHT`, `SPEED`, `HEADING`, `PDOP`, `HDOP`, `VDOP` und die Satellitenspalte `NSAT` auswerten, soweit vorhanden. Andere Spalten SHALL es ohne Warnung übergehen.

#### Scenario: Export eines iBlue 747
- **WHEN** eine Datei die Kopfzeile `INDEX,RCR,DATE,TIME,VALID,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT,SPEED,HEADING` und die Zeile `1,T,2026/11/02,12:00:00,3d,50.000000,N,8.000000,E,100,5.4,45` enthält
- **THEN** entsteht ein Punkt bei 50,0° Nord und 8,0° Ost mit der Zeit 2026-11-02T12:00:00Z, der Höhe 100 m, der Geschwindigkeit 1,5 m/s, dem Kurs 45° und der Fix-Art `3d`

#### Scenario: Andere Spaltenreihenfolge
- **WHEN** eine Datei die Spalten in der Reihenfolge `INDEX,DATE,TIME,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT` hat
- **THEN** werden Position, Zeit und Höhe aus den benannten Spalten gelesen

### Requirement: iBlue-Zeit und -Position
Das Format `iblue-csv` SHALL `DATE` als `JJJJ/MM/TT` oder `TT/MM/JJJJ` lesen und `TIME` als `hh:mm:ss`, wahlweise mit Bruchteilen von Sekunden, zusammen als UTC. `LATITUDE` und `LONGITUDE` SHALL es als Dezimalgrad lesen. Das Vorzeichen SHALL sich allein aus `N/S` bzw. `E/W` ergeben, ein Minuszeichen im Zahlenwert SHALL ignoriert werden. Andere Buchstaben als `N`, `S`, `E` und `W` MUST die Zeile verwerfen.

#### Scenario: Datum eines iBlue 757
- **WHEN** das Feld `DATE` den Wert `02/11/2026` hat
- **THEN** hat der Punkt das Datum 2. November 2026

#### Scenario: Millisekunden
- **WHEN** das Feld `TIME` den Wert `12:00:00.500` hat
- **THEN** hat der Punkt die Zeit 2026-11-02T12:00:00.500Z

#### Scenario: Vorzeichen im Zahlenwert
- **WHEN** eine Zeile die Länge `-8.000456` mit `E/W` = `W` hat
- **THEN** hat der Punkt die Länge -8,000456°

### Requirement: iBlue-Messwerte
Das Format `iblue-csv` SHALL `HEIGHT` als Höhe in Metern, `SPEED` in km/h und `HEADING` als Kurs in Grad lesen. `VALID` SHALL mit den Werten `2d`, `3d` und `DGPS` die Fix-Art ergeben, unabhängig von Groß- und Kleinschreibung; andere Werte ergeben keine. `PDOP`, `HDOP` und `VDOP` SHALL nur übernommen werden, wenn sie größer als 0 sind. Aus `NSAT` SHALL die führende Zahl die Anzahl der genutzten Satelliten ergeben; negative Werte gelten als fehlend.

#### Scenario: Satelliten
- **WHEN** das Feld `NSAT (USED/VIEW)` den Wert `7(10)` hat
- **THEN** hat der Punkt 7 Satelliten

#### Scenario: Unbekannte Werte
- **WHEN** eine Zeile `VALID` = `Unknown`, `PDOP` = `0.000000` und `NSAT` = `-1(` hat
- **THEN** hat der Punkt weder Fix-Art noch PDOP noch Satellitenzahl

### Requirement: Tracks der CSV-Formate
Jede eingelesene Datei SHALL genau einen Track mit einem Segment ergeben, wenn sie mindestens einen gültigen Punkt enthält. Der Track SHALL den Dateinamen ohne Endung als Namen tragen. Werden mehrere Dateien gelesen, SHALL jede einen eigenen Track ergeben, in der Reihenfolge der Übergabe.

#### Scenario: Zwei Aufzeichnungen
- **WHEN** die Dateien `26110201.CSV` und `26110202.CSV` gemeinsam gelesen werden
- **THEN** enthält die Aufzeichnung zwei Tracks mit den Namen `26110201` und `26110202`

### Requirement: Erkennung der CSV-Formate
Die Formaterkennung SHALL eine V-900-Datei daran erkennen, dass ihre erste Zeile nach dem Trimmen der Felder mit den sechs Pflichtspalten des Formats `v900` beginnt. Eine iBlue-CSV-Datei SHALL sie daran erkennen, dass die erste Zeile mit `INDEX` beginnt und alle Pflichtspalten des Formats `iblue-csv` enthält. Andere CSV-Dateien SHALL keines der beiden Formate auslösen.

#### Scenario: V-900-Datei mit Endung .CSV
- **WHEN** die Datei `26110201.CSV` eine V-900-Kopfzeile hat
- **THEN** schlägt die Erkennung das Format `v900` vor

#### Scenario: iBlue-Datei
- **WHEN** eine `.csv`-Datei die Kopfzeile eines iBlue-747-Exports hat
- **THEN** schlägt die Erkennung das Format `iblue-csv` vor

#### Scenario: Fremde CSV-Datei
- **WHEN** eine `.csv`-Datei die Kopfzeile `Name,Vorname,Ort` hat
- **THEN** lautet das Ergebnis „unbekannt“
