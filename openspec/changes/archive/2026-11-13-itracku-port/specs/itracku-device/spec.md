## Purpose

Liest den Speicher des XAiOX iTrackU über die serielle Schnittstelle oder Bluetooth aus, portiert aus gpsbabel 1.7.0. Daraus entsteht ein Track.

## ADDED Requirements

### Requirement: iTrackU erkennen
Der Treiber SHALL mit 4800 Baud `WP AP-Exit` senden, die Eingabe verwerfen und `W'P Camera Detect` senden, beide mit abschließendem Nullbyte. Endet die Antwort nicht innerhalb von 1 Sekunde mit der nullterminierten Kennung `WP GPS+BT`, MUST der Vorgang mit einem Protokollfehler enden, der meldet, dass kein iTrackU gefunden wurde.

#### Scenario: Gerät antwortet
- **WHEN** das Gerät auf die Erkennung `WP GPS+BT` meldet
- **THEN** beginnt der Treiber mit dem Auslesen des Speichers

#### Scenario: Anderes Gerät
- **WHEN** am Anschluss ein Gerät nur NMEA-Sätze sendet
- **THEN** endet der Vorgang nach spätestens 1 Sekunde mit dem Protokollfehler, dass kein iTrackU gefunden wurde

### Requirement: Speicher auslesen
Der Treiber SHALL die Bytes `60 B5 00 00 00 00 00` senden und den folgenden Datenstrom bis zur Endemarke `WP Update Over` lesen. Er SHALL alle vollständigen 16-Byte-Datensätze vor der Endemarke auswerten. Kommen 1 Sekunde lang keine Daten, MUST er den Vorgang mit einer Zeitüberschreitung beenden. Das gilt nicht, wenn die Endemarke schon empfangen wurde.

#### Scenario: Speicher mit Endemarke
- **WHEN** das Gerät 300 Datensätze und dann die Endemarke sendet, die letzten 40 Datensätze im selben Block wie die Marke
- **THEN** liefert der Treiber einen Track „iTrackU“ mit 300 Punkten

#### Scenario: Gerät verstummt
- **WHEN** das Gerät nach 100 Datensätzen ohne Endemarke verstummt
- **THEN** endet der Vorgang mit einer Zeitüberschreitung

### Requirement: Datensätze dekodieren
Ein Datensatz SHALL Länge, Breite und Zeit als 32 Bit, die Höhe in Metern als 16 Bit (alle Little Endian), die Geschwindigkeit in Knoten und ein Kennbyte enthalten. Koordinaten SHALL als Grad · 10⁶ plus Minuten · 10⁴ gelten, Werte über 0x80000000 negativ. Die Zeit (UTC) SHALL Sekunde, Minute, Stunde, Tag, Monat und Jahr ab 2000 in 6, 6, 5, 5, 4 und 6 Bit tragen. Ein Datensatz mit Länge 0xFFFFFFFF MUST entfallen.

#### Scenario: Umrechnung
- **WHEN** ein Datensatz Breite 50300000, Länge 0x80000000 + 8150000, Höhe 123, 10 Knoten und die Zeit 2026-11-02 12:34:56 enthält
- **THEN** liegt der Punkt bei 50,5° N und 8,25° W, 123 m hoch, mit 5,144 m/s und der Zeit 2026-11-02T12:34:56Z

#### Scenario: Leerer Speicherplatz
- **WHEN** ein Datensatz nur aus 0xFF besteht
- **THEN** entsteht daraus kein Punkt

### Requirement: iTrackU im Katalog
Der Gerätekatalog SHALL den Eintrag „XAiOX iTrackU“ mit 4800 Baud und ohne Löschen enthalten.

#### Scenario: iTrackU wählen
- **WHEN** der Anwender „XAiOX iTrackU“ wählt
- **THEN** ist „Speicher löschen …“ nicht verfügbar
