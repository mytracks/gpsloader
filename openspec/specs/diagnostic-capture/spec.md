# diagnostic-capture Specification

## Purpose
Zeichnet die Kommunikation mit Geräten vollständig auf. Anwender können Fehler an Geräten melden, die dem Entwickler nicht zur Verfügung stehen. Aufzeichnungen dienen zugleich als wiederholbare Test-Fixtures.

## Requirements

### Requirement: Aufzeichnung einschalten
Der Anwender SHALL den Diagnose-Mitschnitt in der App ein- und ausschalten können. Standardmäßig MUST er ausgeschaltet sein. Der Zustand SHALL über einen Neustart der App hinweg erhalten bleiben.

#### Scenario: Standardzustand
- **WHEN** die App zum ersten Mal gestartet wird
- **THEN** ist der Diagnose-Mitschnitt ausgeschaltet

#### Scenario: Einschalten
- **WHEN** der Anwender den Mitschnitt einschaltet und danach einen Vorgang startet
- **THEN** wird dieser Vorgang aufgezeichnet

### Requirement: Export für den Support
Der Anwender SHALL die Aufzeichnung des letzten Vorgangs als Datei an einem gewählten Ort speichern können. Vor dem Speichern MUST die App darauf hinweisen, dass die Aufzeichnung Positionsdaten enthält.

#### Scenario: Aufzeichnung sichern
- **WHEN** der Anwender nach einem fehlgeschlagenen Vorgang „Diagnose-Mitschnitt sichern…“ wählt
- **THEN** erhält er einen Hinweis auf enthaltene Positionsdaten und kann die Datei danach speichern

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
