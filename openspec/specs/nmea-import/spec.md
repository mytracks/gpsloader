# nmea-import Specification

## Purpose
Liest NMEA-0183-Dateien von GPS-Loggern und Kameras ein, etwa von Sony GPS CS-1/CS-3, Canon EOS LOG, AMOD und ATP. Daraus entstehen Tracks und Wegpunkte, ohne gpsbabel.

## Requirements

### Requirement: Unterstützte Sätze
Der Import SHALL die Sätze RMC, GGA, GLL, GSA, VTG, ZDA und WPL auswerten. Er SHALL dabei jeden Talker akzeptieren, insbesondere GP, GN, GL, GA, GB, BD und GQ. Andere Sätze, etwa GSV und proprietäre `$P…`-Sätze, SHALL er ohne Warnung ignorieren.

#### Scenario: Multi-GNSS-Logger
- **WHEN** eine Datei `$GNRMC`- und `$GNGGA`-Sätze enthält
- **THEN** werden sie wie `$GPRMC` und `$GPGGA` ausgewertet

#### Scenario: Satellitenstatus
- **WHEN** eine Datei `$GPGSV`-Sätze enthält
- **THEN** werden diese ohne Warnung übergangen

### Requirement: Zeilen und Prüfsummen
Der Import SHALL Zeilen mit LF, CRLF oder CR als Ende akzeptieren. Zeilen, die nicht mit `$` beginnen, SHALL er ignorieren; das betrifft auch die `@`-Zeilen der Sony-Logger. Hat ein Satz eine Prüfsumme und stimmt sie nicht, MUST er verworfen und als Warnung gezählt werden. Sätze ohne Prüfsumme SHALL er akzeptieren.

#### Scenario: Sony-Logdatei
- **WHEN** eine Datei Zeilen enthält, die mit `@` beginnen
- **THEN** werden diese Zeilen übergangen, und die übrigen Sätze werden ausgewertet

#### Scenario: Falsche Prüfsumme
- **WHEN** ein RMC-Satz eine falsche Prüfsumme hat
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt den verworfenen Satz

#### Scenario: Abgeschnittene letzte Zeile
- **WHEN** die letzte Zeile einer Datei mitten im Satz endet
- **THEN** wird sie verworfen, und alle vorherigen Punkte bleiben erhalten

### Requirement: Nur gültige Positionen
Der Import MUST Positionen ohne gültigen Fix verwerfen: RMC und GLL mit Status `V`, GGA mit Fix-Qualität 0 und Sätze ohne Koordinaten. Solche Sätze SHALL keine Warnung erzeugen.

#### Scenario: Logger ohne Empfang
- **WHEN** eine Datei 50 RMC-Sätze mit Status `V` und danach 10 mit Status `A` enthält
- **THEN** enthält der Track 10 Punkte

### Requirement: Ein Punkt pro Zeitpunkt
Sätze mit derselben UTC-Zeit SHALL zu einem Punkt zusammengefasst werden. Dabei gilt:
- Koordinaten, Datum, Geschwindigkeit und Kurs kommen aus RMC.
- Höhe über dem Meeresspiegel, Satellitenanzahl und HDOP kommen aus GGA.
- Fix-Art, PDOP, HDOP und VDOP kommen aus GSA.
- Geschwindigkeit und Kurs kommen ersatzweise aus VTG.

#### Scenario: RMC und GGA zur selben Sekunde
- **WHEN** auf `$GPRMC` um 12:00:01 ein `$GPGGA` um 12:00:01 mit Höhe 94,5 m und 8 Satelliten folgt
- **THEN** entsteht ein einziger Punkt mit den Koordinaten aus RMC, Höhe 94,5 m und 8 Satelliten

#### Scenario: Nur GGA
- **WHEN** eine Datei nur GGA-Sätze enthält
- **THEN** entsteht pro Satz mit gültigem Fix ein Punkt

### Requirement: Datum und Zeit
Der Import SHALL das Datum aus RMC oder ZDA übernehmen. Für Sätze ohne Datum (GGA, GLL) SHALL er das zuletzt bekannte Datum verwenden. Springt die Uhrzeit dabei von kurz vor auf kurz nach Mitternacht, SHALL er das Datum um einen Tag weiterzählen. Punkte vor dem ersten Datum SHALL das erste Datum der Datei erhalten. Zweistellige Jahre SHALL er als 1980 bis 2079 lesen. Alle Zeiten sind UTC; Bruchteile von Sekunden bleiben erhalten.

#### Scenario: Mitternacht
- **WHEN** auf ein RMC vom 02.11.26 um 23:59:59 nur GGA-Sätze um 00:00:00 und 00:00:01 folgen
- **THEN** haben diese Punkte das Datum 3. November 2026

#### Scenario: GGA vor dem ersten RMC
- **WHEN** eine Datei mit drei GGA-Sätzen beginnt und erst danach ein RMC mit Datum folgt
- **THEN** erhalten die drei Punkte das Datum dieses RMC

#### Scenario: Datei ganz ohne Datum
- **WHEN** eine Datei nur GGA-Sätze enthält
- **THEN** haben die Punkte keine Zeit, und eine Warnung weist auf das fehlende Datum hin

### Requirement: Track-Aufteilung
Alle Punkte einer Einlese-Operation SHALL einen Track bilden. Mehrere Dateien werden also zusammengeführt, wie in der Alt-App. Jede Datei SHALL ein neues Segment beginnen. Ebenso SHALL ein neues Segment beginnen, wenn die Zeit eines Punkts vor der des vorherigen liegt.

#### Scenario: Drei Dateien eines Tages
- **WHEN** drei NMEA-Dateien gemeinsam eingelesen werden
- **THEN** enthält die Aufzeichnung einen Track mit drei Segmenten

#### Scenario: Zeitrücksprung
- **WHEN** innerhalb einer Datei auf 10:00:05 ein Punkt mit 09:00:00 folgt
- **THEN** beginnt mit dem zweiten Punkt ein neues Segment

### Requirement: Wegpunkte
WPL-Sätze SHALL als Wegpunkte mit Namen übernommen werden.

#### Scenario: WPL-Satz
- **WHEN** eine Datei `$GPWPL,5144.4694,N,00840.8580,E,HOME*..` enthält
- **THEN** enthält die Aufzeichnung einen Wegpunkt „HOME“ bei 51,741157° N, 8,680967° E

### Requirement: Erkennung
Die Formaterkennung SHALL eine Datei als NMEA 0183 erkennen, wenn unter ihren ersten Zeilen mindestens drei syntaktisch gültige NMEA-Sätze sind.

#### Scenario: Canon-EOS-Log
- **WHEN** eine `.LOG`-Datei der Canon EOS mit einer Kopfzeile und folgenden RMC/GGA-Sätzen geprüft wird
- **THEN** schlägt die Erkennung NMEA 0183 vor
