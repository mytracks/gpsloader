## Purpose

Liest Track und Wegpunkte von Magellan Meridian und SporTrak über die serielle Schnittstelle aus, portiert aus gpsbabel 1.7.0.

## ADDED Requirements

### Requirement: Magellan-Sätze senden und empfangen
Der Treiber SHALL Befehle als `$<Inhalt>*<XX>` mit CR LF senden. XX ist das XOR aller Zeichen des Inhalts in Hex. Er SHALL Zeilen bis LF lesen, CR verwerfen und für jede Zeile höchstens 2 Sekunden warten. Bleibt eine Zeile aus, MUST der Vorgang mit einer Zeitüberschreitung enden.

#### Scenario: Prüfsumme eines Befehls
- **WHEN** der Treiber `PMGNCMD,VERSION` sendet
- **THEN** sendet er `$PMGNCMD,VERSION*` mit dem XOR der Zeichen als zwei Hex-Ziffern und CR LF

#### Scenario: Gerät verstummt
- **WHEN** das Gerät während des Tracks 2 Sekunden lang keine Zeile sendet
- **THEN** endet der Vorgang mit einer Zeitüberschreitung

### Requirement: Verbindung aufbauen
Der Treiber SHALL mit 4800 Baud `PMGNCMD,HANDOFF` und `PMGNCMD,VERSION` senden und höchstens 6 Sekunden auf `$PMGNVER` warten. Kennt er die Produktnummer nicht, MUST der Vorgang mit einem Protokollfehler enden. Eine falsche Prüfsumme vor `$PMGNVER` MUST den Vorgang mit dem Hinweis auf eine falsche Baudrate beenden. Außer bei GPS 315/320 und Map 410 SHALL er `PMGNCMD,NMEAOFF` senden und eine Ablehnung hinnehmen.

#### Scenario: Meridian meldet sich
- **WHEN** das Gerät `$PMGNVER,33,…` sendet
- **THEN** sendet der Treiber `PMGNCMD,NMEAOFF` und liest danach Track und Wegpunkte

#### Scenario: Unbekanntes Gerät
- **WHEN** das Gerät die Produktnummer 99 meldet
- **THEN** endet der Vorgang mit einem Protokollfehler, der die Nummer nennt

#### Scenario: Falsche Baudrate
- **WHEN** vor `$PMGNVER` ein Satz mit falscher Prüfsumme ankommt
- **THEN** endet der Vorgang mit dem Hinweis, die Baudrate zu prüfen

### Requirement: Track und Wegpunkte lesen
Der Treiber SHALL `PMGNCMD,TRACK,2` senden und Tracksätze bis `$PMGNCMD,END` lesen, dann `PMGNCMD,WAYPOINT` und Wegpunktsätze bis `$PMGNCMD,END`. Die Sätze dekodiert er wie in der Spec `magellan-import`. Antwortet das Gerät mit `$PMGNCMD,UNABLE`, SHALL dieser Teil leer bleiben, und der Treiber SHALL das als Schritt melden. Zum Schluss SHALL er `PMGNCMD,HANDOFF` senden. Quittungen sendet er beim Lesen nicht.

#### Scenario: Auslesen
- **WHEN** das Gerät 500 Tracksätze und 20 Wegpunktsätze liefert
- **THEN** liefert der Treiber einen Track „Magellan“ mit 500 Punkten und 20 Wegpunkte

#### Scenario: Keine Wegpunkte
- **WHEN** das Gerät auf `PMGNCMD,WAYPOINT` mit `$PMGNCMD,UNABLE` antwortet
- **THEN** liefert der Treiber den Track ohne Wegpunkte und meldet den Schritt „Gerät sendet keine Wegpunkte“

### Requirement: Magellan-Geräte im Katalog
Der Gerätekatalog SHALL die sieben seriellen Magellan-Geräte der Alt-App mit 4800 Baud und ohne Löschen enthalten.

#### Scenario: Magellan-Gerät wählen
- **WHEN** der Anwender „Magellan SporTrak Map“ wählt
- **THEN** ist „Speicher löschen …“ nicht verfügbar
