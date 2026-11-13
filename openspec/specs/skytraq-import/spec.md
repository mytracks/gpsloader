# skytraq-import Specification

## Purpose
Liest Speicherabbilder von SkyTraq-Venus-Loggern (skytraq-bin), portiert aus gpsbabel 1.7.0. Aus vollen, komprimierten und hochfrequenten Einträgen entstehen Tracks, aus Markierungen Wegpunkte.

## Requirements

### Requirement: Sektoren
Der Import SHALL ein SkyTraq-Speicherabbild in Sektoren zu 4096 Byte lesen; ein kürzerer letzter Sektor SHALL ebenfalls gelesen werden. In jedem Sektor SHALL er Einträge lesen, bis der Sektor endet oder ein Byte `0xFF` den Rest als leer kennzeichnet. Endet ein Sektor auf diese Weise mehr als 18 Byte vor seinem Ende, SHALL der Import das Abbild dort beenden; folgende Sektoren gelten als leer.

#### Scenario: Leerer Sektor beendet das Abbild
- **WHEN** der zweite Sektor nur `0xFF` enthält und der dritte wieder Einträge
- **THEN** stammen alle Punkte aus dem ersten Sektor

#### Scenario: Voller Sektor
- **WHEN** ein Sektor bis auf weniger als 18 Byte mit Einträgen gefüllt ist
- **THEN** liest der Import auch den folgenden Sektor

### Requirement: Volle Einträge
Ein Eintrag vom Typ `0x4` (oberes Halbbyte des ersten Bytes) SHALL als voller Positionsdatensatz mit 18 Byte gelesen werden: Geschwindigkeit in km/h aus den unteren 4 Bit des ersten und dem zweiten Byte, danach Zeit sowie die ECEF-Koordinaten X, Y und Z in Metern als vorzeichenbehaftete 32-Bit-Werte in der Byte-Reihenfolge der Vorlage. Aus der Zeit SHALL die GPS-Woche (untere 10 Bit) und die Sekunde der Woche (Bits ab 12) folgen.

#### Scenario: Zeit eines vollen Eintrags
- **WHEN** das Zeitfeld eines vollen Eintrags die Woche 380 und die Sekunde 302 400 enthält
- **THEN** hat der Punkt die GPS-Woche 380 und die Sekunde 302 400 der Woche

### Requirement: Umrechnung von ECEF
Die ECEF-Koordinaten voller und komprimierter Einträge SHALL nach WGS 84 in Breite, Länge und Höhe über dem Ellipsoid umgerechnet werden.

#### Scenario: Position aus ECEF
- **WHEN** ein voller Eintrag die ECEF-Koordinaten einer Position bei 50,0° Nord, 8,0° Ost und 100 m Höhe enthält
- **THEN** entsteht ein Punkt mit dieser Position auf 0,00001° und 1 m genau und mit der Geschwindigkeit des Eintrags in m/s

### Requirement: Komprimierte Einträge
Ein Eintrag vom Typ `0x8` SHALL als komprimierter Datensatz mit 8 Byte gelesen werden: Geschwindigkeit wie beim vollen Eintrag, ein Zeitabstand in Sekunden (16 Bit, Big Endian) und drei Positionsänderungen zu je 10 Bit. Werte über 511 SHALL als negativ gelten (511 minus Wert). Zeit und ECEF-Koordinaten SHALL vom vorherigen Eintrag aus fortgeschrieben werden.

#### Scenario: Fortgeschriebene Position
- **WHEN** auf einen vollen Eintrag ein komprimierter mit Zeitabstand 5 und den Änderungen +3, -2 und +1 m folgt
- **THEN** liegt der zweite Punkt 5 Sekunden nach dem ersten, an der um diese Werte verschobenen ECEF-Position

### Requirement: Einträge mit hoher Rate
Ein Eintrag vom Typ `0x2` SHALL als Datensatz mit 20 Byte gelesen werden: GPS-Woche aus den unteren 2 Bit des ersten und dem zweiten Byte, Geschwindigkeit in km/h (16 Bit), Zeit in Millisekunden der Woche (untere 30 Bit), Breite und Länge in Einheiten von 2⁻²⁰ Grad und Höhe in Einheiten von 2⁻⁷ m. Die Millisekunden SHALL erhalten bleiben.

#### Scenario: Zehn Punkte pro Sekunde
- **WHEN** zwei Einträge mit hoher Rate 100 ms auseinander liegen
- **THEN** unterscheiden sich die Zeiten der beiden Punkte um 0,1 s

### Requirement: Markierungen
Einträge vom Typ `0x6` (wie voll) und `0xC` (wie hohe Rate) SHALL als Markierungen (POI) gelesen werden: Sie SHALL einen Trackpunkt und zusätzlich einen Wegpunkt mit Position, Zeit und Höhe des Punkts ergeben. Die Wegpunkte SHALL `POI` gefolgt von ihrer laufenden Nummer im Abbild heißen.

#### Scenario: Taste gedrückt
- **WHEN** das Abbild nach zwei vollen Einträgen einen Eintrag vom Typ `0x6` enthält
- **THEN** entstehen drei Trackpunkte und ein Wegpunkt `POI 1` an der Position des dritten

### Requirement: Zeit
Die Zeit eines Punkts SHALL aus GPS-Woche und Sekunde der Woche ab dem 6. Januar 1980 berechnet und mit den Schaltsekunden bis einschließlich 2017 (GPS minus UTC = 18 s) nach UTC umgerechnet werden. Weil die Woche nur 10 Bit hat, SHALL der Import den Wochenzyklus wählen, der die Zeit in die 1024 Wochen bis zum Zeitpunkt des Lesens legt.

#### Scenario: Aktueller Wochenzyklus
- **WHEN** ein Eintrag die GPS-Woche 380 und die Sekunde 302 400 enthält und das Abbild im November 2026 gelesen wird
- **THEN** hat der Punkt die Zeit 2026-07-22T11:59:42Z (GPS-Woche 2428)

### Requirement: Fehlerhafte Abbilder
Ein Eintrag mit unbekanntem Typ oder ein Eintrag, der über das Ende des Sektors hinausreicht, SHALL das Lesen des Abbilds an dieser Stelle beenden. Die bis dahin gelesenen Punkte SHALL erhalten bleiben, und eine Warnung SHALL das abgeschnittene Abbild melden. Ein komprimierter Eintrag ohne vorherigen vollen Eintrag SHALL verworfen und als Warnung gezählt werden.

#### Scenario: Unbekannter Eintrag
- **WHEN** nach drei gültigen Einträgen ein Byte mit dem Typ `0x1` folgt
- **THEN** enthält der Track drei Punkte, und eine Warnung meldet das abgeschnittene Abbild

#### Scenario: Komprimierter Eintrag am Anfang
- **WHEN** das Abbild mit einem komprimierten Eintrag beginnt
- **THEN** entsteht daraus kein Punkt, und eine Warnung zählt den verworfenen Datensatz

### Requirement: Track
Jedes Abbild SHALL einen Track mit einem Segment ergeben, der nach der Datei ohne Endung heißt. Mehrere Abbilder SHALL mehrere Tracks in der Reihenfolge der Übergabe ergeben.

#### Scenario: Abbild aus gpsbabel
- **WHEN** die Datei `venus.bin` gelesen wird
- **THEN** heißt der Track `venus`

### Requirement: Erkennung
Die Formaterkennung SHALL ein SkyTraq-Abbild daran erkennen, dass die Einträge am Anfang des ersten Sektors gültige Typen haben, bis zum ersten `0xFF` oder dem Ende des geprüften Bereichs lückenlos aufeinander folgen, mindestens ein voller Eintrag darunter ist und dessen ECEF-Position zwischen 6 300 km und 6 450 km vom Erdmittelpunkt entfernt liegt.

#### Scenario: Abbild mit Endung .bin
- **WHEN** eine Datei `log.bin` mit einem gültigen ersten Sektor geprüft wird
- **THEN** schlägt die Erkennung `skytraq-bin` vor

#### Scenario: Andere Binärdatei
- **WHEN** eine Datei mit zufälligen Bytes oder eine FIT-Datei geprüft wird
- **THEN** schlägt die Erkennung nicht `skytraq-bin` vor
