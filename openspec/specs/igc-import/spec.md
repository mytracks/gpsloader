# igc-import Specification

## Purpose
Liest IGC-Flugaufzeichnungen nach der FAI-Spezifikation ein, wie sie Vario-Geräte, Flarm und Flug-Apps schreiben. Daraus entstehen Tracks, ohne gpsbabel.

## Requirements

### Requirement: Datensätze
Der Import SHALL die Datei zeilenweise lesen und Zeilen mit LF, CRLF oder CR als Ende akzeptieren. Er SHALL B-Records (Positionsfixe), den I-Record (Erweiterungen der B-Records) und den H-Record `HFDTE` (Datum) auswerten. Alle anderen Datensätze, insbesondere A-, C-, E-, F-, G-, K- und L-Records, SHALL er ohne Warnung ignorieren.

#### Scenario: Aufgabendeklaration
- **WHEN** eine Datei C-Records mit Wendepunkten enthält
- **THEN** entstehen daraus weder Wegpunkte noch Warnungen

#### Scenario: Signatur
- **WHEN** eine Datei am Ende G-Records enthält
- **THEN** werden diese übergangen, und die Signatur wird nicht geprüft

### Requirement: Positionsfixe
Ein B-Record SHALL nach diesem festen Aufbau gelesen werden: Zeit `HHMMSS` (UTC), Breite `DDMMmmm` mit `N` oder `S`, Länge `DDDMMmmm` mit `E` oder `W`, Gültigkeit `A` oder `V`, Druckhöhe und GNSS-Höhe mit je fünf Stellen in Metern, gegebenenfalls mit führendem Minus. Ein B-Record, der kürzer als 35 Zeichen ist, ungültige Ziffern oder eine Position außerhalb des gültigen Bereichs enthält, MUST verworfen und als Warnung gezählt werden.

#### Scenario: Gültiger Fix
- **WHEN** die Datei den B-Record `B1101355206343N00006198WA0058700558` enthält
- **THEN** entsteht ein Punkt bei 52,105717° Nord und 0,103300° West mit der Zeit 11:01:35 UTC und der Höhe 558 m

#### Scenario: Südlich und östlich
- **WHEN** ein B-Record `S` und `E` als Hemisphären hat
- **THEN** ist die Breite negativ und die Länge positiv

#### Scenario: Abgeschnittener Datensatz
- **WHEN** ein B-Record nach 20 Zeichen endet
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt den verworfenen Datensatz

### Requirement: Höhe und Fix-Art
Der Import SHALL als Höhe die GNSS-Höhe verwenden, wenn die Gültigkeit `A` ist und die GNSS-Höhe nicht 0 ist. Sonst SHALL er die Druckhöhe verwenden, wenn sie nicht 0 ist, sonst keine Höhe. Die Gültigkeit `A` SHALL als Fix-Art `3d` und `V` als `2d` übernommen werden.

#### Scenario: Gerät ohne Drucksensor
- **WHEN** ein B-Record die Gültigkeit `A`, Druckhöhe `00000` und GNSS-Höhe `00412` hat
- **THEN** hat der Punkt die Höhe 412 m und die Fix-Art `3d`

#### Scenario: Fix ohne GNSS-Höhe
- **WHEN** ein B-Record die Gültigkeit `V`, Druckhöhe `00380` und GNSS-Höhe `00000` hat
- **THEN** hat der Punkt die Höhe 380 m und die Fix-Art `2d`

#### Scenario: Keine Höhe
- **WHEN** Druckhöhe und GNSS-Höhe beide `00000` sind
- **THEN** hat der Punkt keine Höhe

### Requirement: Erweiterungen
Der Import SHALL den I-Record auswerten, der Anzahl, Anfangs- und Endposition sowie Kürzel der Erweiterungen in den B-Records angibt. Ist die Erweiterung `SIU` vorhanden, SHALL ihr Wert als Anzahl der Satelliten übernommen werden. Andere Erweiterungen SHALL er ohne Warnung übergehen. Ein B-Record, der kürzer ist als eine angekündigte Erweiterung, SHALL trotzdem als Punkt ohne diese Erweiterung gelten.

#### Scenario: Satelliten
- **WHEN** der I-Record `I023638FXA3940SIU` lautet und ein B-Record an Position 39–40 den Wert `09` hat
- **THEN** hat der Punkt 9 Satelliten

#### Scenario: Unbekannte Erweiterung
- **WHEN** der I-Record nur `GSP` und `TRT` ankündigt
- **THEN** werden die Punkte ohne Satellitenzahl und ohne Warnung gelesen

### Requirement: Datum und Zeit
Der Import SHALL das Datum aus dem H-Record `HFDTE` lesen, sowohl in der Form `HFDTEddmmyy` als auch `HFDTEDATE:ddmmyy,nn`. Zweistellige Jahre SHALL als 1980–2079 gelesen werden. Ist die Zeit eines B-Records kleiner als die des vorherigen, SHALL das Datum um einen Tag weitergezählt werden. Fehlt das Datum, SHALL der Import die Punkte ohne Zeit übernehmen und eine Warnung erzeugen.

#### Scenario: Neue Schreibweise
- **WHEN** die Datei `HFDTEDATE:150726,01` enthält
- **THEN** haben die Punkte das Datum 15. Juli 2026

#### Scenario: Flug über Mitternacht
- **WHEN** das Datum 31.12.2025 ist und auf einen B-Record um 23:59:58 einer um 00:00:02 folgt
- **THEN** hat der zweite Punkt die Zeit 2026-01-01T00:00:02Z

#### Scenario: Fehlendes Datum
- **WHEN** eine Datei keinen `HFDTE`-Record hat
- **THEN** haben die Punkte keine Zeit, und eine Warnung nennt die Anzahl der Punkte ohne Datum

### Requirement: Tracks
Jede eingelesene Datei SHALL genau einen Track mit einem Segment ergeben. Der Track SHALL den Dateinamen ohne Endung als Namen tragen. Werden mehrere Dateien gelesen, SHALL jede einen eigenen Track ergeben.

#### Scenario: Zwei Flüge
- **WHEN** die Dateien `flug1.igc` und `flug2.igc` gemeinsam gelesen werden
- **THEN** enthält die Aufzeichnung zwei Tracks mit den Namen `flug1` und `flug2`

### Requirement: Erkennung
Die Formaterkennung SHALL eine Datei als IGC erkennen, wenn ihre erste nicht leere Zeile ein A-Record ist (`A` gefolgt von drei Buchstaben oder Ziffern) und der erkannte Anfang mindestens einen H- oder B-Record enthält. Die Dateiendung `.igc` SHALL nur als Hinweis dienen.

#### Scenario: Endung fehlt
- **WHEN** eine IGC-Datei die Endung `.txt` hat
- **THEN** schlägt die Erkennung IGC vor

#### Scenario: Keine IGC-Datei
- **WHEN** eine NMEA-Datei die Endung `.igc` hat
- **THEN** schlägt die Erkennung NMEA 0183 vor
