# diagnostic-capture Specification

## Purpose
Zeichnet die Kommunikation mit Geräten vollständig auf. Anwender können Fehler an Geräten melden, die dem Entwickler nicht zur Verfügung stehen. Aufzeichnungen dienen zugleich als wiederholbare Test-Fixtures.

## Requirements

### Requirement: Lesbares und maschinenlesbares Format
Das Format MUST zeilenweise, textbasiert und versioniert sein. Bytes SHALL als Hexadezimalzeichen erscheinen, druckbare ASCII-Zeichen zusätzlich als Text, damit Menschen die Datei lesen und Programme sie verarbeiten können.

#### Scenario: Datei im Texteditor
- **WHEN** eine Aufzeichnung eines NMEA-artigen Dialogs im Texteditor geöffnet wird
- **THEN** sind die gesendeten und empfangenen Zeilen als Text erkennbar

### Requirement: Wiedergabe in Tests
Eine Aufzeichnung eines seriellen Dialogs MUST sich als Mock-Transport wiedergeben lassen. Ein Treiber erhält dabei auf seine gesendeten Bytes die aufgezeichneten Antworten. Weicht der Treiber vom aufgezeichneten Dialog ab, MUST die Wiedergabe das mit Position und Inhalt melden.

#### Scenario: Wiedergabe eines erfolgreichen Auslesens
- **WHEN** ein Treiber gegen die Wiedergabe einer erfolgreichen Aufzeichnung läuft
- **THEN** liefert er dasselbe Ergebnis wie beim aufgezeichneten Vorgang

#### Scenario: Abweichung
- **WHEN** der Treiber an Position 5 andere Bytes sendet als aufgezeichnet
- **THEN** schlägt die Wiedergabe mit erwarteten und tatsächlichen Bytes an Position 5 fehl

### Requirement: Begrenzter Speicherbedarf
Aufzeichnungen MUST ausschließlich lokal gespeichert werden. Die App SHALL nur die Aufzeichnungen der letzten 10 Vorgänge aufbewahren und ältere automatisch löschen.

#### Scenario: Elfter Vorgang
- **WHEN** bei eingeschaltetem Mitschnitt der elfte Vorgang aufgezeichnet wird
- **THEN** wird die älteste Aufzeichnung gelöscht

### Requirement: Inhalt des Mitschnitts
Eine Aufzeichnung MUST enthalten:
- Kopfdaten: App-Version, macOS-Version, Architektur, ob unter Rosetta, Treiber, Port und Parameter
- alle gesendeten und empfangenen Bytes in der tatsächlichen Reihenfolge, je mit Zeitstempel in Millisekunden
- Ereignisse wie Öffnen, Schließen, Zeitüberschreitung, Abbruch und Fehler

#### Scenario: Serieller Dialog
- **WHEN** ein Treiber bei eingeschaltetem Mitschnitt 16 Bytes sendet und 3 Bytes empfängt
- **THEN** enthält die Aufzeichnung einen Eintrag „gesendet“ mit den 16 Bytes und danach einen Eintrag „empfangen“ mit den 3 Bytes, jeweils mit Zeitstempel

#### Scenario: App unter Rosetta
- **WHEN** der Anwender die App selbst unter Rosetta gestartet hat und einen Vorgang aufzeichnet
- **THEN** vermerken die Kopfdaten, dass die App unter Rosetta läuft

### Requirement: Aufzeichnung immer aktiv
Die App SHALL jeden Lese- und Löschvorgang aufzeichnen. Einen Schalter zum Abschalten SHALL es nicht geben. Aufzeichnungen MUST lokal bleiben, bis der Anwender sie in ein Support-Paket übernimmt.

#### Scenario: Erster Start
- **WHEN** die App zum ersten Mal gestartet wird und der Anwender ein Gerät ausliest
- **THEN** liegt danach ein Mitschnitt dieses Vorgangs vor

#### Scenario: Fehlgeschlagener Vorgang
- **WHEN** ein Vorgang mit einem Fehler endet
- **THEN** wird sein Mitschnitt ebenso gespeichert wie der eines erfolgreichen Vorgangs
