## ADDED Requirements

### Requirement: Befehle
Der Treiber SHALL Befehle mit `0x93` beginnen, auf 16 Byte auffüllen und das letzte Byte so setzen, dass die Summe aller Bytes null ist. Beim GT-800 SHALL er den Befehl am Stück senden, bei USB-Modellen in zwei Stücken zu 8 Byte, deren erstes mit leerer Antwort quittiert wird. Jede Antwort SHALL mit `0x93` und einer vorzeichenbehafteten Länge (16 Bit, Big Endian) beginnen; Bytes davor SHALL er verwerfen. Eine negative Länge SHALL als Gerätefehler bis zu dreimal wiederholt werden.

#### Scenario: Gerätefehler
- **WHEN** das Gerät auf einen Befehl einmal mit `93 FF FE` antwortet
- **THEN** wiederholt der Treiber den Befehl und liest danach alle Punkte

### Requirement: Auslesen
Der Treiber SHALL das Gerät in den Konfigurationsmodus schalten (`93 01 01 03`), die Anzahl der Datensätze abfragen (`93 0B 03 00 1D`; beim GT-800 mit zwei zusätzlichen Bits), die Datensätze ab Adresse `0x1000` in Blöcken zu 4 KiB lesen (`93 05 07`) und das Gerät danach in den NMEA-Modus zurückschalten.

#### Scenario: GT-800 auslesen
- **WHEN** ein GT-800 150 Datensätze meldet
- **THEN** liest der Treiber zwei Blöcke und liefert die gültigen Punkte

#### Scenario: USB-Modell auslesen
- **WHEN** ein GT-200 über USB-HID 150 Datensätze meldet
- **THEN** liefert der Treiber dieselben Punkte wie beim GT-800

### Requirement: Datensätze
Ein Datensatz SHALL 32 Byte lang sein (Big Endian): Merkmale (`0x04` Wegpunkt, `0x10` ungültig, `0x40` Track-Beginn, `0xF1` Debug-Text), Jahr modulo 16 und Monat, Tag, Stunde, Minute, Millisekunden der Minute, Breite und Länge in 10⁻⁷ Grad sowie GPS-Höhe in Zentimetern. Das Jahr SHALL das letzte passende Jahr bis zum aktuellen sein. Gültig SHALL ein Datensatz ohne Ungültig-Merkmal sein, beim GT-800 mit mehr als vier genutzten Satelliten, bei USB-Modellen mit mindestens einem.

#### Scenario: Jahr modulo 16
- **WHEN** im November 2026 ein Datensatz das Jahr modulo 16 = 11 enthält
- **THEN** liegt der Punkt im Jahr 2011

#### Scenario: Wenige Satelliten
- **WHEN** ein Datensatz drei genutzte Satelliten meldet
- **THEN** übernimmt ihn der Treiber nur bei USB-Modellen

### Requirement: Speicher löschen (experimentell)
Der Treiber SHALL Löschen als experimentell anbieten: Er SHALL vom Ende des Speichers abwärts den ersten belegten Block suchen und ab dort jeden Block mit den undokumentierten Schreibbefehlen löschen, beim GT-800 aus 0x700 Blöcken, beim GT-100 aus 0x80, beim GT-120 aus 0x200 und beim GT-200 aus 0x100. Für andere USB-Modelle MUST das Löschen mit einem Protokollfehler enden.

#### Scenario: Speicher löschen (experimentell)
- **WHEN** der Anwender die Warnung bestätigt und zwei Blöcke belegt sind
- **THEN** löscht der Treiber die Blöcke 2 und 1

#### Scenario: Modell ohne Löschfunktion
- **WHEN** ein GT-200e gelöscht werden soll
- **THEN** endet der Vorgang mit dem Hinweis, dass Löschen für dieses Modell nicht unterstützt wird

### Requirement: USB-HID-Verbindung
Für USB-Modelle SHALL die App das Gerät über Hersteller- und Produktkennung (`0x0DF7`/`0x0900`) finden, exklusiv öffnen, Befehle als Output-Reports zu 8 Byte senden und Antworten aus den Input-Reports lesen, mit Zeitlimit und Diagnose-Mitschnitt. Ist kein Gerät angeschlossen, MUST der Vorgang mit „Gerät nicht gefunden“ enden.

#### Scenario: Kein i-GotU angeschlossen
- **WHEN** der Anwender ein USB-Modell ausliest und kein Gerät angeschlossen ist
- **THEN** meldet die App, dass das Gerät nicht gefunden wurde

### Requirement: i-GotU-Geräte im Katalog
Der Gerätekatalog SHALL die fünf USB-Modelle ohne Portwahl und den GT-800 und GT-800 Pro mit seriellem Anschluss enthalten.

#### Scenario: i-GotU-Geräte im Katalog
- **WHEN** der Anwender ein USB-Modell wählt
- **THEN** zeigt das Fenster keine Portwahl
