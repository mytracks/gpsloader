# magellan-import Specification

## Purpose
Liest die SD-Dateien von Magellan Meridian und eXplorist ein, portiert aus gpsbabel 1.7.0. Daraus entstehen ein Track und, aus Wegpunktdateien, Wegpunkte.

## Requirements

### Requirement: Magellan-Sätze dekodieren
Ein Tracksatz `$PMGNTRK` SHALL Breite (ddmm.mmm, N/S), Länge (dddmm.mmm, E/W), Höhe in Metern, Einheit, Zeit (hhmmss.ss, UTC), ein festes Feld, einen optionalen Namen und das Datum (ddmmyy, Jahr ab 2000) liefern. Ein Wegpunktsatz `$PMGNWPL` SHALL Breite, Länge, Höhe, Einheit, Namen, Kommentar und Symbol liefern. Im Kommentar MUST eine Folge aus ESC (0x1B) und zwei Hex-Ziffern als das bezeichnete Zeichen gelten.

#### Scenario: Tracksatz
- **WHEN** der Satz `$PMGNTRK,5030.000,N,00815.000,W,00100,M,123456.50,A,,021126` mit Prüfsumme gelesen wird
- **THEN** entsteht ein Punkt bei 50,5° N und 8,25° W, 100 m hoch, mit der Zeit 2026-11-02T12:34:56.5Z

#### Scenario: Wegpunkt mit Komma im Kommentar
- **WHEN** ein Wegpunktsatz den Namen `HOME` und den Kommentar `A<ESC>2CB` enthält
- **THEN** entsteht ein Wegpunkt `HOME` mit dem Kommentar `A,B`

### Requirement: Magellan-SD-Dateien lesen
Das Format `magellan` SHALL die Dateien von Meridian und eXplorist zeilenweise lesen. Tracksätze ergeben einen Track mit dem Dateinamen ohne Endung. Wegpunktsätze ergeben Wegpunkte, aber nur in Dateien mit der Endung `.upt`, wie in der Vorlage. `$PMGNCMD,END` beendet die Datei. Eine falsche Prüfsumme MUST eine Warnung ergeben, der Satz zählt trotzdem. Zeilen, die nicht mit `$` beginnen, MUST das Format mit einer Warnung überspringen.

#### Scenario: Tracklog-Datei
- **WHEN** die Datei `TRACK01.LOG` 50 Tracksätze und 2 Wegpunktsätze enthält
- **THEN** entsteht ein Track `TRACK01` mit 50 Punkten und kein Wegpunkt

#### Scenario: Wegpunktdatei
- **WHEN** die Datei `POI.UPT` 3 Wegpunktsätze enthält
- **THEN** entstehen 3 Wegpunkte

#### Scenario: Falsche Prüfsumme
- **WHEN** ein Tracksatz eine falsche Prüfsumme trägt
- **THEN** enthält der Track den Punkt, und das Ergebnis enthält eine Warnung mit der Zeilennummer

### Requirement: Erkennung von Magellan-Dateien
Das Format SHALL eine Datei erkennen, wenn in den ersten 4096 Byte ein Satz `$PMGNTRK`, `$PMGNWPL` oder `$PMGNRTE` mit gültiger Prüfsumme steht. Es SHALL die Endungen `log`, `upt` und `rte` angeben.

#### Scenario: NMEA-Datei
- **WHEN** eine Datei nur `$GPRMC`- und `$GPGGA`-Sätze enthält
- **THEN** erkennt das Format sie nicht
