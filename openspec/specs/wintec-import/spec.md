# wintec-import Specification

## Purpose
Liest die Dateien der Wintec-Logger: TES (WBT-202), BIN-Speicherabbilder (WBT-100/200) und TK1 (WBT-201, G-Rays 2, WSG-1000), portiert aus gpsbabel 1.7.0. Daraus entstehen Tracks und Wegpunkte.

## Requirements

### Requirement: Wintec-Zeitstempel
Die Wintec-Formate SHALL Zeiten als 32-Bit-Wert lesen: Sekunde (Bits 0–5), Minute (6–11), Stunde (12–16), Tag (17–21), Monat (22–25) und Jahr ab 2000 (26–31), als UTC.

#### Scenario: Zeitstempel
- **WHEN** ein Zeitstempel 2026-11-02 12:30:15 in diesen Bits codiert
- **THEN** hat der Punkt die Zeit 2026-11-02T12:30:15Z

### Requirement: TES-Dateien
Das Format `wintec-tes` SHALL eine Datei als Folge von Datensätzen zu 16 Byte lesen (Little Endian): Merkmale (16 Bit), Zeitstempel, Breite und Länge in 10⁻⁷ Grad (32 Bit mit Vorzeichen) und Höhe in Metern (16 Bit mit Vorzeichen). Jeder Datensatz SHALL einen Trackpunkt ergeben, mit dem Merkmal `0x02` zusätzlich einen Wegpunkt. Ein unvollständiger letzter Datensatz SHALL eine Warnung ergeben.

#### Scenario: Aufzeichnung eines WBT-202
- **WHEN** eine TES-Datei drei Datensätze enthält, der zweite mit dem Merkmal `0x02`
- **THEN** entstehen ein Track mit drei Punkten und ein Wegpunkt `POI 1` an der Position des zweiten

#### Scenario: Abgeschnittene TES-Datei
- **WHEN** eine TES-Datei nach zwei Datensätzen und 5 weiteren Bytes endet
- **THEN** entstehen zwei Punkte und eine Warnung über die abgeschnittene Datei

### Requirement: BIN-Dateien
Das Format `wbt-bin` SHALL Datensätze zu 12 Byte (Zeitstempel, Breite, Länge in 10⁻⁷ Grad) oder 16 Byte (zusätzlich Höhe in Dezimetern) lesen. Es SHALL die erste Länge wählen, von der die Dateigröße ein Vielfaches ist und für die alle Zeitstempel gültig sind (Jahr ab 2004); passt keine, MUST das Lesen mit einem Fehler enden. Eine Breite ab 100° (bzw. bis -100°) SHALL einen neuen Track beginnen; 100° werden dann abgezogen (bzw. addiert).

#### Scenario: Neuer Track im Norden
- **WHEN** der dritte von fünf Datensätzen die Breite 150,0° hat
- **THEN** entstehen zwei Tracks mit zwei und drei Punkten, und der dritte Punkt liegt bei 50,0°

#### Scenario: Datensätze mit Höhe
- **WHEN** eine BIN-Datei Datensätze zu 16 Byte mit der Höhe 1234 (Dezimeter) enthält
- **THEN** haben die Punkte die Höhe 123,4 m

#### Scenario: Keine gültige Länge
- **WHEN** eine BIN-Datei 13 Byte groß ist
- **THEN** endet das Lesen mit einem Fehler, der die Datei nennt

### Requirement: TK1-Dateien
Das Format `wbt-tk1` SHALL Dateien lesen, die mit `WintecLogFormat` und einem Nullbyte beginnen. Ab Offset `0x400` SHALL es Datensätze zu 16 Byte lesen: Merkmale (16 Bit), Zeitstempel, Breite, Länge (10⁻⁷ Grad) und Höhe in Metern (vorzeichenbehaftet, 16 Bit). Datensätze aus lauter Nullbytes SHALL übersprungen werden, der Zeitstempel `0x04000000` SHALL das Ende markieren. Das Merkmal `0x01` SHALL einen neuen Track beginnen und `0x02` zusätzlich einen Wegpunkt ergeben.

#### Scenario: Zwei Tracks und ein Wegpunkt
- **WHEN** eine TK1-Datei fünf Datensätze enthält, der erste und vierte mit `0x01`, der zweite mit `0x02`, gefolgt vom Endkennzeichen und weiteren Datensätzen
- **THEN** entstehen zwei Tracks mit drei und zwei Punkten und ein Wegpunkt; die Datensätze nach dem Endkennzeichen werden nicht gelesen

### Requirement: Tracknamen der Wintec-Formate
Ergibt eine Datei einen Track, SHALL er den Dateinamen ohne Endung tragen; mehrere Tracks SHALL zusätzlich ihre laufende Nummer in Klammern tragen. Wegpunkte SHALL `POI` gefolgt von ihrer laufenden Nummer in der Datei heißen.

#### Scenario: Mehrere Tracks
- **WHEN** die Datei `log.tk1` zwei Tracks ergibt
- **THEN** heißen sie `log (1)` und `log (2)`

### Requirement: Erkennung der Wintec-Formate
Die Formaterkennung SHALL `wbt-tk1` am Kopf `WintecLogFormat` erkennen. Sie SHALL `wbt-bin` erkennen, wenn die vollständigen Datensätze im geprüften Bereich für 12 oder 16 Byte gültige Zeitstempel und Längen von höchstens 180° haben. Sie SHALL `wintec-tes` erkennen, wenn mindestens zwei Datensätze zu 16 Byte im geprüften Bereich Merkmale von höchstens `0x0007`, gültige Zeitstempel, Breiten von höchstens 90° und Längen von höchstens 180° haben.

#### Scenario: TK1-Datei
- **WHEN** eine Datei mit dem Kopf `WintecLogFormat` geprüft wird
- **THEN** schlägt die Erkennung `wbt-tk1` vor

#### Scenario: TES-Datei
- **WHEN** die Datei `TRK0001.TES` mit gültigen Datensätzen geprüft wird
- **THEN** schlägt die Erkennung `wintec-tes` vor

#### Scenario: Andere Abbilder
- **WHEN** ein SkyTraq- oder MTK-Abbild geprüft wird
- **THEN** schlägt die Erkennung keines der Wintec-Formate vor
