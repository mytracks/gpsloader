# mtk-import Specification

## Purpose
Liest Speicherabbilder von MTK-Loggern (mtk-bin) und Holux-Loggern (m241-bin), portiert aus gpsbabel 1.7.0. Daraus entstehen Tracks und Wegpunkte mit Positionsqualität.

## Requirements

### Requirement: Kopf
Der Import SHALL aus dem Kopf am Anfang des Abbilds die Formatmaske (Bytes 2–5, Little Endian) übernehmen. Ist die Aufzeichnungsart (Bytes 6–7) weder `0x0104` noch `0x0106` und ist die Datei größer als 64 KiB, SHALL er den Kopf des zweiten Blocks verwenden.

#### Scenario: Ungültiger erster Kopf
- **WHEN** der Kopf des ersten Blocks die Aufzeichnungsart `0x0000` hat und der zweite Block einen gültigen Kopf
- **THEN** gilt die Formatmaske des zweiten Kopfs

### Requirement: Blöcke
Der Import SHALL das Abbild in Blöcken zu 64 KiB lesen, die Datensätze eines Blocks ab Offset `0x200`. Vier Bytes `0xFF` oder das Blockende SHALL den Block beenden, und das Lesen SHALL im nächsten Block bei `0x200` weitergehen.

#### Scenario: Zwei Blöcke
- **WHEN** der erste Block nach drei Datensätzen mit `0xFF` aufgefüllt ist und der zweite Block ab `0x200` zwei weitere enthält
- **THEN** ergibt das Abbild fünf Punkte

### Requirement: Felder der Datensätze
Jeder Datensatz SHALL die Felder enthalten, deren Bit in der Formatmaske gesetzt ist, in aufsteigender Bitreihenfolge und Little Endian. Ausgewertet werden Zeit (UTC, Sekunden seit 1970), Gültigkeit, Breite, Länge, Höhe, Geschwindigkeit (km/h), Kurs, PDOP, HDOP und VDOP (Hundertstel), genutzte Satelliten und Millisekunden; die übrigen Felder SHALL nur übersprungen werden. Ein Datensatz ohne Breite oder Länge SHALL keinen Punkt ergeben.

#### Scenario: Datensatz eines iBlue 747
- **WHEN** die Formatmaske Zeit, Gültigkeit, Breite, Länge, Höhe und Geschwindigkeit enthält und ein Datensatz 2026-11-02T12:00:00Z, SPS, 50,0°, 8,0°, 100 m und 36 km/h codiert
- **THEN** entsteht ein Punkt mit diesen Werten, der Fix-Art `3d` und der Geschwindigkeit 10 m/s

#### Scenario: Millisekunden
- **WHEN** die Formatmaske Millisekunden enthält und ein Datensatz den Wert 500 hat
- **THEN** liegt die Zeit des Punkts 0,5 s nach der vollen Sekunde

### Requirement: Prüfsumme
Bei MTK-Loggern SHALL nach den Feldern ein `*` und eine Prüfsumme folgen, bei Holux nur die Prüfsumme. Die Prüfsumme SHALL das XOR aller Feldbytes sein. Fehlt bei einem MTK-Logger das `*` und steht dort `0xFF`, SHALL der Datensatz ohne Punkt übersprungen werden.

#### Scenario: Falsche Prüfsumme
- **WHEN** die Prüfsumme eines Datensatzes nicht stimmt
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt den Datensatz

### Requirement: Satellitendaten
Ist das Bit für Satellitendaten gesetzt, SHALL der Datensatz für jeden gesehenen Satelliten einen Block aus Kennung, Nutzung und Anzahl sowie, falls gesetzt, Elevation, Azimut und Signalstärke enthalten. Die Anzahl der Blöcke SHALL aus dem ersten Block folgen; bei 0 Satelliten SHALL ein Block ohne die optionalen Felder folgen. Diese Daten SHALL übersprungen, aber in die Prüfsumme einbezogen werden.

#### Scenario: Drei Satelliten
- **WHEN** ein Datensatz Satellitendaten für drei Satelliten mit Elevation, Azimut und Signalstärke enthält
- **THEN** wird der folgende Datensatz an der richtigen Stelle gelesen, und die Prüfsumme stimmt

### Requirement: Fix-Art
Die Gültigkeit SHALL so übernommen werden: `0x0001` ergibt die Fix-Art `none`, `0x0002` ergibt `3d`, `0x0004` ergibt `dgps`; alle anderen Werte ergeben keine Fix-Art. Ein Punkt ohne Fix oder mit unbekannter Fix-Art an der Position 90° N/0° oder 0°/0° SHALL verworfen werden.

#### Scenario: Unsinnige Position
- **WHEN** ein Datensatz die Gültigkeit `0x0001` und die Position 0°/0° hat
- **THEN** entsteht daraus kein Punkt

### Requirement: Info-Blöcke
Ein Block aus sieben Bytes `0xAA`, einem Typ, vier Datenbytes und vier Bytes `0xBB` SHALL als Info-Block gelesen werden und keinen Punkt ergeben. Typ `0x02` SHALL die Formatmaske ab dem folgenden Datensatz ändern.

#### Scenario: Neue Formatmaske
- **WHEN** ein Info-Block vom Typ `0x02` die Millisekunden aus der Formatmaske entfernt
- **THEN** werden die folgenden Datensätze ohne dieses Feld gelesen

### Requirement: Tracks
Bei MTK-Loggern SHALL ein Info-Block vom Typ `0x07` mit dem Wert `0x0106` (Logger eingeschaltet) einen neuen Track beginnen, bei Holux eine Änderung von Intervall (Typ `0x03`) oder Distanz (Typ `0x04`). Ein Abbild mit einem Track SHALL den Dateinamen ohne Endung als Tracknamen tragen; mehrere Tracks SHALL zusätzlich ihre laufende Nummer in Klammern tragen.

#### Scenario: Logger zweimal eingeschaltet
- **WHEN** zwischen zwei Gruppen von Datensätzen ein Info-Block „Logger eingeschaltet“ steht
- **THEN** enthält die Aufzeichnung zwei Tracks `log (1)` und `log (2)` für die Datei `log.bin`

### Requirement: Wegpunkte
Ein Datensatz, dessen Aufzeichnungsgrund das Bit `0x0008` (Taste) enthält, SHALL zusätzlich einen Wegpunkt an derselben Position ergeben. Bei Holux SHALL ein Datensatz nach der Kennung `HOLUX…WAYPNT` ebenso einen Wegpunkt ergeben. Die Wegpunkte SHALL `POI` gefolgt von ihrer laufenden Nummer heißen.

#### Scenario: Taste gedrückt
- **WHEN** ein Datensatz den Aufzeichnungsgrund `0x0008` hat
- **THEN** entstehen ein Trackpunkt und ein Wegpunkt `POI 1`

### Requirement: Holux
Das Format `m241-bin` SHALL Breite und Länge als 32-Bit-Gleitkommazahlen und die Höhe als die oberen drei Bytes einer 32-Bit-Gleitkommazahl lesen und das Bit 31 der Formatmaske ignorieren. Kennungen `HOLUX…` mit 16 Byte (gefolgt von vier optionalen Leerzeichen) SHALL übersprungen werden. Nach der Kennung `HOLUXGR245` oder `HOLUXM1200` SHALL der Import die Höhe aus dem Feld der Geschwindigkeit und die Geschwindigkeit in cm/s aus dem Feld der Höhe lesen.

#### Scenario: Holux M-241
- **WHEN** ein Holux-Abbild einen Datensatz mit 50,0°, 8,0° und 100 m enthält
- **THEN** entsteht ein Punkt mit dieser Position auf die Genauigkeit einer 32-Bit-Gleitkommazahl und mit 100 m Höhe

#### Scenario: Holux GPSport 245
- **WHEN** nach der Kennung `HOLUXGR245LOGGER` ein Datensatz im Feld der Höhe 500 und im Feld der Geschwindigkeit 120 m codiert
- **THEN** hat der Punkt die Geschwindigkeit 5 m/s und die Höhe 120 m

### Requirement: Erkennung der MTK-Formate
Die Formaterkennung SHALL ein MTK-Abbild an einem Kopf mit gesetztem Zeit-Bit in der Formatmaske, gültiger Aufzeichnungsart und einem Info-Block, einer Holux-Kennung oder einem Datensatz mit gültiger Prüfsumme bei `0x200` erkennen. Enthält der Bereich ab `0x200` eine Kennung `HOLUX` oder ist das Bit 31 der Formatmaske gesetzt, SHALL sie `m241-bin` vorschlagen, sonst `mtk-bin`.

#### Scenario: Abbild eines iBlue 747
- **WHEN** die Datei `data.bin` eines MTK-Loggers geprüft wird
- **THEN** schlägt die Erkennung `mtk-bin` vor

#### Scenario: Abbild eines Holux M-241
- **WHEN** ein Abbild mit der Kennung `HOLUXGR241LOGGER` geprüft wird
- **THEN** schlägt die Erkennung `m241-bin` vor

#### Scenario: SkyTraq-Abbild
- **WHEN** ein SkyTraq-Abbild geprüft wird
- **THEN** schlägt die Erkennung weder `mtk-bin` noch `m241-bin` vor
