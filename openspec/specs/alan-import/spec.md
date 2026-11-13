# alan-import Specification

## Purpose
Liest die Tracklog-Dateien (`.trl`) des Alan Map500 ein, portiert aus gpsbabel 1.7.0. Daraus entstehen bis zu acht Tracks ohne Zeitstempel.

## Requirements

### Requirement: Aufbau der Alan-Tracklog-Datei
Das Format `alantrl` SHALL eine Datei als vier Blöcke zu 0x10000 Byte mit je zwei Tracklogs lesen, gefolgt vom Kopf an Offset 0x40000, alle Werte Little Endian. Ein Tracklog besteht aus 2500 Koordinatenpaaren x/y (je 32 Bit) und danach 2500 Paaren aus Geschwindigkeit und Höhe (je 16 Bit). Ist die Datei zu kurz oder steht am Kopf nicht die Kennung `0x38CB1200`, MUST das Lesen mit dem Hinweis enden, dass es keine Alan-Datei ist.

#### Scenario: Falsche Kennung
- **WHEN** eine 0x40170 Byte lange Datei am Offset 0x40000 eine andere Kennung trägt
- **THEN** endet das Lesen mit dem Fehler, dass die Datei keine Alan-Tracklog-Datei ist

#### Scenario: Zu kurze Datei
- **WHEN** die Datei kürzer als 0x40170 Byte ist
- **THEN** endet das Lesen mit demselben Fehler

### Requirement: Tracks und Punkte
Für jeden der acht Track-Köpfe mit gesetztem Belegt-Feld SHALL das Format einen Track bilden. Der Name ist das Namensfeld ohne nachfolgende Leerzeichen und Nullbytes. Er enthält die ersten `totalpt` Punkte des zugehörigen Tracklogs. Breite SHALL −y/36000 Grad sein, Länge x/36000 Grad, Höhe Wert/5 Meter, Geschwindigkeit Wert/720 m/s, eine negative Geschwindigkeit entfällt. Punkte haben keine Zeit.

#### Scenario: Zwei belegte Tracks
- **WHEN** die Köpfe 0 und 3 belegt sind, mit 100 und 2500 Punkten
- **THEN** entstehen zwei Tracks in dieser Reihenfolge, mit 100 und 2500 Punkten und den Namen aus den Köpfen

#### Scenario: Umrechnung
- **WHEN** ein Punkt x = 288000, y = −1800000, Höhe 500 und Geschwindigkeit 7200 hat
- **THEN** liegt er bei 50° N, 8° O, 100 m Höhe, mit 10 m/s und ohne Zeit

#### Scenario: Zu große Punktzahl
- **WHEN** ein Kopf mehr als 2500 Punkte meldet
- **THEN** liest das Format 2500 Punkte und gibt eine Warnung aus

### Requirement: Erkennung von Alan-Dateien
Das Format SHALL eine Datei erkennen, wenn ihre ersten 4096 Byte vorhanden sind und alle 512 Koordinatenpaare darin plausibel sind (|x| ≤ 180 · 36000, |y| ≤ 90 · 36000). Es MUST die Endung `trl` angeben.

#### Scenario: Textdatei mit Endung trl
- **WHEN** eine Textdatei mit der Endung `.trl` gewählt wird
- **THEN** erkennt das Format sie nicht als Alan-Datei
