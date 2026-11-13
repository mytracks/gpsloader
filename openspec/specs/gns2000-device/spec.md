# gns2000-device Specification

## Purpose
Liest den Track des Bluetooth-Loggers GNS 2000 (auch GNS 2000 plus) aus und löscht seinen Speicher, clean-room in GPSLoggerKit nach dem eigenen myTracks-Treiber des Entwicklers.

## Requirements

### Requirement: GNS-2000-Sätze
Der Treiber SHALL Befehle als `$<Inhalt>*<xx>` mit CR LF senden, wobei `xx` das XOR aller Zeichen des Inhalts als zwei Hex-Ziffern in Kleinbuchstaben ist. Er SHALL CR-LF-Zeilen lesen. Zeilen mit fehlender oder falscher Prüfsumme MUST er ignorieren; die Prüfsumme gilt ohne Rücksicht auf Groß- und Kleinschreibung.

#### Scenario: Prüfsumme eines Befehls
- **WHEN** der Treiber den Lesebefehl sendet
- **THEN** sendet er `$PGNS,R*` mit dem XOR von `PGNS,R` als zwei Hex-Ziffern in Kleinbuchstaben und CR LF

#### Scenario: Gestörte Zeile
- **WHEN** eine `$PMTKLOX`-Zeile eine falsche Prüfsumme hat
- **THEN** wertet der Treiber sie nicht aus und liest weiter

### Requirement: Bereitschaft des Geräts
Nach dem Öffnen der Verbindung SHALL der Treiber auf die erste Zeile warten, die mit `$` beginnt, weil das Gerät laufend NMEA-Sätze sendet. Erst danach SHALL er seinen Befehl senden. Kommt innerhalb von 10 Sekunden keine solche Zeile, MUST der Vorgang mit einer Zeitüberschreitung enden.

#### Scenario: Gerät sendet NMEA
- **WHEN** das Gerät nach dem Öffnen `$GPGGA,…` sendet
- **THEN** sendet der Treiber danach seinen Befehl

#### Scenario: Gerät stumm
- **WHEN** das Gerät nach dem Öffnen 10 Sekunden lang nichts sendet
- **THEN** endet der Vorgang mit einer Zeitüberschreitung

### Requirement: Speicher lesen
Der Treiber SHALL `PGNS,R` senden und auf `$PMTKLOX,0,<Anzahl>` warten. Danach SHALL er `$PMTKLOX,1,<Index>,<Wörter…>` bis `$PMTKLOX,2` lesen und den Fortschritt als gelesene von angekündigten Paketen melden. Je vier Wörter aus 8 Hex-Ziffern bilden in Textreihenfolge einen 16-Byte-Datensatz. Vergehen zwischen zwei Zeilen 10 Sekunden ohne Daten, MUST der Vorgang mit einer Zeitüberschreitung enden.

#### Scenario: Auslesen
- **WHEN** das Gerät 3 Pakete mit zusammen 40 Datensätzen ankündigt und sendet
- **THEN** liefert der Treiber die gültigen Punkte daraus und meldet den Fortschritt von 0 bis 3 Paketen

#### Scenario: Ende fehlt
- **WHEN** das Gerät nach dem letzten Datenpaket verstummt
- **THEN** endet der Vorgang nach 10 Sekunden mit einer Zeitüberschreitung

### Requirement: Datensätze
Ein Datensatz SHALL im Little-Endian-Format den Unix-Zeitstempel (UInt32, UTC) an 0, den Fix-Typ (UInt8) an 4, Breite und Länge (Float32) an 5 und 9 und die Höhe in Metern (Int16) an 13 enthalten. Datensätze aus lauter `FF` und solche mit einem Fix-Typ außerhalb von 1 bis 4 MUST der Treiber verwerfen.

#### Scenario: Umrechnung
- **WHEN** ein Datensatz den Zeitstempel 1793620800, Fix-Typ 3, Breite 50,5, Länge 8,25 und Höhe 123 enthält
- **THEN** entsteht ein Punkt bei 50,5° N und 8,25° O, 123 m hoch, mit der Zeit 2026-11-02T12:00:00Z

#### Scenario: Ungültiger Fix
- **WHEN** ein Datensatz den Fix-Typ 0 hat
- **THEN** entsteht daraus kein Punkt

### Requirement: Tracks des GNS 2000
Ist der Zeitstempel eines Punkts kleiner als der des vorigen, SHALL der Treiber einen neuen Track beginnen. Jeder Track SHALL nach der Zeit seines ersten Punkts heißen, im Format `yyyy-MM-dd HH:mm` in UTC. Leere Tracks entfallen.

#### Scenario: Zeit springt zurück
- **WHEN** auf Punkte vom 2026-11-02 Punkte vom 2026-11-01 folgen
- **THEN** entstehen zwei Tracks, „2026-11-02 12:00“ und „2026-11-01 08:00“

### Requirement: Speicher des GNS 2000 löschen
Der Treiber SHALL `PGNS,C` senden und auf `$PMTK001` warten. Nach jeweils mehr als 10 Zeilen in Folge, die nicht mit `$P` beginnen, SHALL er den Befehl erneut senden, höchstens fünfmal insgesamt. Kommt keine Bestätigung, MUST der Vorgang mit einem Protokollfehler enden.

#### Scenario: Löschen bestätigt
- **WHEN** das Gerät nach `PGNS,C` mit `$PMTK001,…` antwortet
- **THEN** endet das Löschen erfolgreich

#### Scenario: Gerät überhört den Befehl
- **WHEN** das Gerät nach dem ersten `PGNS,C` nur NMEA-Sätze sendet
- **THEN** sendet der Treiber den Befehl nach 11 solchen Zeilen erneut

### Requirement: GNS 2000 im Katalog
Der Gerätekatalog SHALL einen Eintrag „GNS 2000“ mit der Verbindungsart Bluetooth enthalten. Er gilt für die Gerätenamen „GNS 2000“ und „GNS 2000 plus“ und den SDP-Dienst „GNS GPS“. Er SHALL ohne Anschlusswahl auskommen und Löschen anbieten.

#### Scenario: GNS 2000 wählen
- **WHEN** der Anwender „GNS 2000“ wählt
- **THEN** zeigt das Fenster keine Anschlusswahl, und „Auslesen“ und „Speicher löschen …“ sind verfügbar
