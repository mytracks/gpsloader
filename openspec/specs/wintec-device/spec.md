# wintec-device Specification

## Purpose
Liest und löscht Wintec WBT-100/200/201, G-Rays 2 und WSG-1000 über die serielle Schnittstelle, portiert aus gpsbabel 1.7.0, mit Erkennung des Gerätetyps.

## Requirements

### Requirement: Gerätetyp erkennen
Der Treiber SHALL den Gerätetyp in bis zu fünf Runden bestimmen: WBT-200, wenn auf `$PFST,NORMAL` bei 9600 Baud `$PFST` zurückkommt; WBT-201, wenn auf `@AL` bei 57600 Baud `@AL` zurückkommt; WSG-1000, wenn auf `@AL,2,3` die Antwort `@AL,2,3,OK` kommt. Antwortet keiner, MUST der Vorgang mit einem Protokollfehler enden.

#### Scenario: Kein Wintec-Gerät
- **WHEN** am Anschluss kein Gerät antwortet
- **THEN** endet der Vorgang mit dem Hinweis, dass der Gerätetyp nicht bestimmt werden kann

### Requirement: Auslesen WBT-100/200
Beim WBT-200 SHALL der Treiber nach `$PFST,READLOGGER` einen Kopf von 6 Byte mit der Punktanzahl (Bytes 2–3 plus 1) lesen und danach die Datensätze, zuerst als 12-Byte-, sonst als 16-Byte-Datensätze, je nachdem, für welche Länge alle Zeitstempel gültig sind. Die Datensätze SHALL wie eine Datei `wbt-bin` dekodiert werden.

#### Scenario: WBT-200
- **WHEN** ein WBT-200 fünf Datensätze zu 16 Byte liefert, darunter einen Track-Beginn
- **THEN** entstehen zwei Tracks mit zwei und drei Punkten und Höhen

### Requirement: Auslesen WBT-201 und WSG-1000
Beim WBT-201 und WSG-1000 SHALL der Treiber Beginn und Ende der Aufzeichnung und des Speicherbereichs abfragen (`@AL,5,1`, `5,2`, `5,9`, `5,10`), den Bereich in Stücken bis 4 KiB lesen (`@AL,5,3,<Position>`) und jedes Stück an seiner XOR-Prüfsumme (`@AL,CS,…`) prüfen. Fehlerhafte Stücke SHALL er erneut anfordern, nach zehn Fehlern MUST der Vorgang enden. Liegt das Ende vor dem Beginn, SHALL er bis zum Ende des Bereichs und dann vom Anfang des Bereichs lesen.

#### Scenario: WBT-201 mit Prüfsumme
- **WHEN** das erste Stück mit falscher Prüfsumme ankommt
- **THEN** fordert der Treiber es erneut an und liefert alle Punkte

#### Scenario: Überschriebener Ringpuffer
- **WHEN** die Aufzeichnung über das Ende des Speicherbereichs hinaus fortgesetzt wurde
- **THEN** liefert der Treiber die Punkte in der Reihenfolge der Aufzeichnung

### Requirement: Speicher löschen
Der Treiber SHALL beim WBT-200 die Dateien 27 bis 31 entfernen und die Bereiche 0 bis 3 freigeben, beim WBT-201 und WSG-1000 `@AL,5,6` senden.

#### Scenario: Speicher löschen
- **WHEN** der Anwender das Löschen bestätigt
- **THEN** sendet der Treiber die Löschbefehle des erkannten Gerätetyps

### Requirement: Wintec-Geräte im Katalog
Der Gerätekatalog SHALL die fünf Wintec-Geräte der Alt-App mit einem gemeinsamen Treiber enthalten und Löschen anbieten.

#### Scenario: Wintec-Geräte im Katalog
- **WHEN** der Anwender die Geräteliste öffnet
- **THEN** enthält sie G-Rays 2, WBT-100, WBT-200, WBT-201 und WSG-1000
