# locosys-import Specification

## Purpose
Liest die Datenlogger-Dateien (SBP) und SiRF-Binärdateien (SBN) der Locosys-Logger GT-11, GT-31 und BGT-31, portiert aus gpsbabel 1.7.0. Daraus entstehen Tracks.

## Requirements

### Requirement: SBP-Kopf
Das Format `sbp` SHALL die ersten 64 Byte einer Datei als Kopf überspringen. Eine Datei unter 64 Byte MUST mit einem Fehler enden, der die Datei nennt.

#### Scenario: Zu kurze Datei
- **WHEN** eine SBP-Datei 40 Byte groß ist
- **THEN** endet das Lesen mit einem Fehler

### Requirement: SBP-Datensätze
Das Format `sbp` SHALL nach dem Kopf Datensätze zu 32 Byte lesen (Little Endian): HDOP in Fünfteln (Byte 0), Satelliten (Byte 1), Millisekunden (Bytes 2–3, modulo 1000), gepackte Zeit (Bytes 4–7), Breite und Länge in 10⁻⁷ Grad (Bytes 12–19), Höhe in Zentimetern (Bytes 20–23), Geschwindigkeit in cm/s (Bytes 24–25) und Kurs in Hundertstelgrad (Bytes 26–27). Alle Datensätze SHALL einen Track ergeben, der nach der Datei heißt; ein unvollständiger letzter Datensatz SHALL eine Warnung ergeben.

#### Scenario: Datensatz eines GT-31
- **WHEN** ein Datensatz 2026-11-02T12:00:00.250Z, 50,0°, 8,0°, 123,45 m, 250 cm/s, 9000 (90°), 7 Satelliten und HDOP 5 codiert
- **THEN** entsteht ein Punkt mit diesen Werten, der Geschwindigkeit 2,5 m/s, dem Kurs 90° und HDOP 1,0

### Requirement: Gepackte SBP-Zeit
Die gepackte Zeit SHALL aus Sekunde (Bits 0–5), Minute (6–11), Stunde (12–16), Tag (17–21) und `Jahr × 12 + Monat` (Bits 22–31, Jahr ab 2000) bestehen, als UTC. Ein Wert, dessen Rest modulo 12 null ist, SHALL den Dezember des Vorjahrs bezeichnen.

#### Scenario: Dezember
- **WHEN** die Monatsbits `26 × 12 + 12` enthalten
- **THEN** liegt der Punkt im Dezember 2026

### Requirement: SBN-Pakete
Das Format `sbn` SHALL eine Datei als Folge von SiRF-Paketen lesen: `0xA0 0xA2`, Länge (16 Bit, Big Endian), Nutzdaten, Prüfsumme (Summe der Nutzdaten, 15 Bit, Big Endian) und `0xB0 0xB3`. Das erste Paket MUST vom Typ 253 (Geräteinformation) sein, sonst endet das Lesen mit einem Fehler. Pakete vom Typ 13 (Satellitenliste) SHALL übergangen werden.

#### Scenario: Keine SBN-Datei
- **WHEN** das erste Paket vom Typ 41 ist
- **THEN** endet das Lesen mit einem Fehler, der die Datei nennt

### Requirement: Beschädigte SBN-Pakete
Ein Paket mit falscher Prüfsumme SHALL verworfen und gezählt werden. Ein beschädigter Paketrahmen SHALL das Lesen mit einer Warnung über die abgeschnittene Datei beenden.

#### Scenario: Falsche Prüfsumme
- **WHEN** das zweite von drei Navigationspaketen eine falsche Prüfsumme hat
- **THEN** entstehen zwei Punkte und eine Warnung

### Requirement: SBN-Navigationsdaten
Ein Paket vom Typ 41 SHALL einen Trackpunkt ergeben (Big Endian, Offsets in den Nutzdaten ohne Typbyte): Gültigkeit (Bytes 0–1), Modus (Byte 3), Jahr, Monat, Tag, Stunde, Minute und Millisekunden der Minute (Bytes 10–17), Breite und Länge in 10⁻⁷ Grad (Bytes 22–29), Höhe in Zentimetern (Bytes 34–37), Geschwindigkeit in cm/s (Bytes 39–40), Kurs in Hundertstelgrad (Bytes 41–42), Satelliten (Byte 87) und HDOP in Fünfteln (Byte 88).

#### Scenario: Navigationspaket
- **WHEN** ein Navigationspaket 2026-11-02T12:00:01.500Z, 50,0°, 8,0° und 100 m codiert
- **THEN** entsteht ein Punkt mit diesen Werten

### Requirement: SBN-Fix-Art
Bei Gültigkeit 0 SHALL der Modus (Bits 0–2) die Fix-Art ergeben: 3 und 5 `2d`, 4 und 6 `3d` (mit gesetztem Bit 7 `dgps`), sonst `none`. Bei anderer Gültigkeit SHALL die Fix-Art `none` sein.

#### Scenario: Gültiger 3D-Fix mit DGPS
- **WHEN** ein Navigationspaket die Gültigkeit 0 und den Modus `0x84` hat
- **THEN** hat der Punkt die Fix-Art `dgps`

#### Scenario: Ungültige Lösung
- **WHEN** ein Navigationspaket die Gültigkeit `0x0001` hat
- **THEN** hat der Punkt die Fix-Art `none`

### Requirement: Erkennung der Locosys-Formate
Die Formaterkennung SHALL `sbn` an einem ersten SiRF-Paket vom Typ 253 mit gültiger Prüfsumme und gültigem Rahmen erkennen. Sie SHALL `sbp` erkennen, wenn der Kopf ab Byte 7 eine durch Kommas getrennte Geräteinformation aus druckbaren ASCII-Zeichen enthält oder Byte 6 den Wert `0xFD` hat, und der erste Datensatz eine gültige Zeit (Jahr ab 2004), eine Breite von höchstens 90° und eine Länge von höchstens 180° hat.

#### Scenario: SBN-Datei
- **WHEN** eine Datei mit einem Informationspaket am Anfang geprüft wird
- **THEN** schlägt die Erkennung `sbn` vor

#### Scenario: SBP-Datei
- **WHEN** eine Datei mit Locosys-Kopf und gültigem erstem Datensatz geprüft wird
- **THEN** schlägt die Erkennung `sbp` vor

#### Scenario: Andere Dateien
- **WHEN** eine SkyTraq-, MTK- oder Wintec-Datei geprüft wird
- **THEN** schlägt die Erkennung weder `sbp` noch `sbn` vor
