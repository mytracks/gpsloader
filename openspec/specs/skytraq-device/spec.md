# skytraq-device Specification

## Purpose
Liest und löscht Logger mit SkyTraq-Venus-Chipsatz (Canmore, MiniHomer u. a.) über die serielle Schnittstelle, portiert aus gpsbabel 1.7.0, mit automatischer Suche der Baudrate.

## Requirements

### Requirement: Nachrichtenrahmen
Der Treiber SHALL Nachrichten als `0xA0 0xA1`, Länge (16 Bit, Big Endian), Nutzdaten, XOR-Prüfsumme der Nutzdaten und `0x0D 0x0A` senden und empfangen. Vor dem Senden SHALL er ungelesene Eingangsdaten verwerfen. Eine Nachricht SHALL bis zu dreimal gesendet werden, bis das Gerät sie mit `0x83` und ihrer Kennung bestätigt; `0x84` gilt als Ablehnung. Eine Bestätigung mit Kennung 0 SHALL übergangen werden. Eine falsche Prüfsumme MUST den Vorgang mit einem Protokollfehler beenden.

#### Scenario: Prüfsummenfehler
- **WHEN** die Bestätigung des Geräts eine falsche Prüfsumme hat
- **THEN** endet der Vorgang mit einem Protokollfehler

### Requirement: Baudrate finden
Der Treiber SHALL die Baudrate des Geräts finden, indem er nacheinander 9600, 230400, 115200, 57600, 4800, 19200 und 38400 Baud einstellt und die Software-Version abfragt (`0x02 0x01`, Antwort `0x80`). Ist für das Gerät eine Anfangsrate festgelegt, SHALL er nur diese versuchen. Antwortet das Gerät auf keiner Rate, MUST der Vorgang mit einem Protokollfehler enden.

#### Scenario: Bekannte Baudrate
- **WHEN** für das Gerät 38400 Baud festgelegt sind
- **THEN** stellt der Treiber nur 38400 Baud ein

#### Scenario: Kein Logger
- **WHEN** am Anschluss kein Gerät antwortet
- **THEN** endet der Vorgang mit dem Hinweis, dass kein SkyTraq-Logger gefunden wurde

### Requirement: Auslesen
Der Treiber SHALL auf die Download-Rate des Geräts umschalten (Befehl `0x05`), den Logstatus abfragen (`0x17`, Antwort `0x94`) und belegte Sektoren plus einen lesen. Er SHALL bis zu 255 Sektoren auf einmal anfordern (`0x1D`), nach einem Fehler weniger, und nach einer Ablehnung einzeln (`0x1B`). Ein leerer Sektor SHALL das Lesen beenden. Danach SHALL er die ursprüngliche Baudrate wiederherstellen und das Gerät neu starten.

#### Scenario: Auslesen
- **WHEN** ein Logger mit 38400 Baud zwei belegte Sektoren meldet
- **THEN** liest der Treiber mit 230400 Baud, stellt danach 38400 Baud wieder ein, startet das Gerät neu und liefert die Punkte der Sektoren

#### Scenario: Einzelne Sektoren
- **WHEN** das Gerät das Lesen mehrerer Sektoren ablehnt
- **THEN** liest der Treiber die Sektoren einzeln und liefert dieselben Punkte

### Requirement: Dekodieren des Downloads
Die gelesenen Sektoren SHALL wie ein Speicherabbild dekodiert werden (`skytraq-import`), mit der Ausnahme, dass nur ein leerer Sektor das Abbild beendet.

#### Scenario: Teilweise gefüllter Sektor
- **WHEN** auf einen teilweise gefüllten Sektor ein weiterer mit Daten folgt, der noch zu den gelesenen gehört
- **THEN** werden auch dessen Punkte übernommen, wie bei gpsbabel

### Requirement: Speicher löschen
Der Treiber SHALL den Speicher mit dem Befehl `0x19` löschen und das Gerät danach neu starten.

#### Scenario: Speicher löschen
- **WHEN** der Anwender das Löschen bestätigt
- **THEN** sendet der Treiber den Löschbefehl, und das Gerät wird neu gestartet

### Requirement: SkyTraq-Geräte im Katalog
Der Gerätekatalog SHALL die SkyTraq-Geräte der Alt-App mit deren Baudraten enthalten (Anfangsrate und Download-Rate, Standard 230400) und Löschen anbieten.

#### Scenario: Geräte im Katalog
- **WHEN** der Anwender die Geräteliste öffnet
- **THEN** enthält sie die elf SkyTraq-Geräte, und „Canmore GT-750F“ arbeitet mit 38400 Baud
