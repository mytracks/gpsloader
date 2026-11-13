## ADDED Requirements

### Requirement: Befehle
Der Treiber SHALL Befehle als NMEA-artige Sätze mit XOR-Prüfsumme senden und Antwortzeilen lesen, bis eine Zeile mit der erwarteten Kennung kommt oder die Wartezeit abläuft. Andere Zeilen, insbesondere laufende NMEA-Ausgabe, SHALL er übergehen. Eine Quittung `$PMTK001` für denselben Befehl mit dem Ergebnis 0, 1 oder 2 SHALL als Ablehnung gelten.

#### Scenario: NMEA-Ausgabe dazwischen
- **WHEN** das Gerät vor jeder Antwort einen `$GPGGA`-Satz sendet
- **THEN** liest der Treiber die Antworten trotzdem richtig

### Requirement: Gerät erkennen
Der Treiber SHALL das Modell mit `$PMTK605` abfragen (Antwort `$PMTK705`). Antwortet das Gerät nicht, MUST der Vorgang mit einem Protokollfehler enden. Meldet es „GR-245“, SHALL er den Holux-Handshake vor und nach dem Vorgang senden.

#### Scenario: Kein MTK-Logger
- **WHEN** das Gerät auf die Modellabfrage nicht antwortet
- **THEN** endet der Vorgang mit dem Hinweis, dass es kein MTK-Logger ist

### Requirement: Auslesen
Der Treiber SHALL den Logstatus abfragen, das Logging pausieren, die Flash-Belegung abfragen und den Speicher in Blöcken zu 1 KiB ab Adresse 0 lesen, bis die belegte Größe (aufgerundet auf 64 KiB) erreicht ist oder ein Block nur `0xFF` enthält. Danach SHALL er das Logging wieder einschalten, wenn es eingeschaltet war, und das Abbild wie eine Datei `mtk-bin` bzw. `m241-bin` dekodieren.

#### Scenario: Auslesen
- **WHEN** ein MTK-Logger zwei belegte 64-KiB-Blöcke hat
- **THEN** liefert der Treiber dieselben Punkte wie das Speicherabbild, und das Logging ist danach wieder eingeschaltet

### Requirement: Sonderfälle beim Lesen
Ist die Belegung unbekannt, SHALL der Treiber das Ende durch Lesen am Anfang jedes 64-KiB-Blocks suchen. Abgelehnte oder unbeantwortete Blöcke SHALL er bis zu dreimal anfordern.

#### Scenario: Belegung unbekannt
- **WHEN** das Gerät die Flash-Belegung nicht meldet
- **THEN** findet der Treiber das Ende der Daten und liefert dieselben Punkte

#### Scenario: Abgelehnter Block
- **WHEN** das Gerät die erste Leseanfrage ablehnt
- **THEN** fordert der Treiber den Block erneut an

#### Scenario: Holux M-241
- **WHEN** ein Holux M-241 ausgelesen wird
- **THEN** arbeitet der Treiber mit 38400 Baud und dekodiert das Abbild im Holux-Format

### Requirement: Speicher löschen
Der Treiber SHALL das Logging pausieren, den Speicher mit `$PMTK182,6,1` löschen, bis zu 30 Sekunden auf die Bestätigung warten und das Logging danach wieder einschalten, wenn es eingeschaltet war.

#### Scenario: Speicher löschen
- **WHEN** der Anwender das Löschen bestätigt
- **THEN** wird der Speicher gelöscht, und das Logging ist danach wieder eingeschaltet

### Requirement: MTK-Geräte im Katalog
Der Gerätekatalog SHALL die MTK-Geräte der Alt-App mit 115200 Baud und die Holux-Geräte mit 38400 Baud enthalten und Löschen anbieten.

#### Scenario: MTK-Geräte im Katalog
- **WHEN** der Anwender die Geräteliste öffnet
- **THEN** enthält sie neun MTK- und zwei Holux-Geräte
