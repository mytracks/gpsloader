# file-conversion Specification

## Purpose
Der Dateimodus von gpsloader: Dateien von Speicherkarte oder USB-Speicher, deren Format GPSLoggerKit nativ liest, auswählen und als GPX-Datei speichern, ohne gpsbabel und ohne Rosetta.

## Requirements

### Requirement: Dateien auswählen
Die App SHALL den Befehl „Dateien konvertieren…“ im Menü „Ablage“ (⌘O) und als Schaltfläche im Bereich „Dateien konvertieren“ anbieten, dazu dort eine Ablagefläche. Der Befehl SHALL auf diesen Bereich schalten und einen Dateidialog für eine oder mehrere Dateien öffnen. Auf das Hauptfenster gezogene Dateien SHALL die App in jedem Bereich annehmen, auf „Dateien konvertieren“ schalten und konvertieren.

#### Scenario: Auswahl über das Menü
- **WHEN** der Anwender „Ablage > Dateien konvertieren…“ wählt und zwei NMEA-Dateien auswählt
- **THEN** startet die Konvertierung dieser beiden Dateien

#### Scenario: Drag & Drop
- **WHEN** der Anwender eine IGC-Datei aus dem Finder auf das Hauptfenster zieht
- **THEN** startet die Konvertierung dieser Datei

#### Scenario: Ordner gezogen
- **WHEN** der Anwender einen Ordner auf das Hauptfenster zieht
- **THEN** nimmt die App ihn nicht an

#### Scenario: Drag & Drop im Gerätebereich
- **WHEN** der Bereich „Gerät auslesen“ gezeigt wird und der Anwender eine NMEA-Datei auf das Fenster zieht
- **THEN** zeigt das Fenster den Bereich „Dateien konvertieren“, und die Konvertierung startet

### Requirement: Unterstützte Formate
Die App SHALL alle Formate ihres Katalogs konvertieren. Der Katalog SHALL aus den Formaten von GPSLoggerKit und von GPSLoggerKitGPL bestehen. Das Format jeder Datei SHALL über die Formaterkennung auf diesem Katalog bestimmt werden. Kommt ein Format zu einem der beiden Pakete hinzu, SHALL es ohne Änderung an der App verfügbar sein. Der Dateidialog SHALL alle Dateien zur Auswahl zulassen, weil die Endung nur ein Hinweis ist.

#### Scenario: NMEA mit Endung .LOG
- **WHEN** der Anwender die Datei `GPS_20261102.LOG` einer Canon EOS wählt
- **THEN** wird sie als NMEA 0183 erkannt und konvertiert

#### Scenario: Neues Format im Katalog
- **WHEN** GPSLoggerKit oder GPSLoggerKitGPL ein weiteres Format in seinen Katalog aufnimmt
- **THEN** konvertiert die App Dateien dieses Formats, ohne dass ihr Code geändert wird

#### Scenario: Format aus dem GPL-Paket
- **WHEN** die Konvertierung mit einem Katalog geprüft wird, der zusätzlich ein Testformat enthält, und eine Datei dieses Formats gewählt wird
- **THEN** wird sie mit dem Testformat gelesen und in die GPX-Datei übernommen

### Requirement: Nicht erkannte Dateien
Erkennt GPSLoggerKit das Format einer Datei nicht, SHALL die App diese Datei mit Namen nennen und anbieten, ohne sie fortzufahren oder abzubrechen. Ist keine der Dateien erkannt, SHALL die App nur melden, dass das Format nicht unterstützt wird, und nichts konvertieren.

#### Scenario: Eine von drei Dateien unbekannt
- **WHEN** der Anwender zwei NMEA-Dateien und ein JPEG-Bild wählt
- **THEN** nennt die App das Bild als nicht unterstützt und bietet „Ohne diese Datei fortfahren“ und „Abbrechen“ an

#### Scenario: Nur unbekannte Dateien
- **WHEN** der Anwender ausschließlich eine PDF-Datei wählt
- **THEN** meldet die App, dass das Format nicht unterstützt wird, und zeigt keinen Sicherungsdialog

### Requirement: Mehrere Dateien zusammenführen
Mehrere Dateien SHALL eine einzige GPX-Datei ergeben. Dateien desselben Formats SHALL in der gewählten Reihenfolge gemeinsam gelesen werden, sodass die Regeln des Formats für mehrere Dateien gelten. Die Ergebnisse verschiedener Formate SHALL in der Reihenfolge ihres ersten Auftretens zusammengefügt werden: erst alle Tracks, dann alle Wegpunkte.

#### Scenario: Zwei NMEA-Dateien
- **WHEN** der Anwender zwei NMEA-Dateien mit je 100 Punkten konvertiert
- **THEN** enthält die GPX-Datei einen Track mit zwei Segmenten und 200 Punkten

#### Scenario: Gemischte Formate
- **WHEN** der Anwender eine GPX-Datei mit einem Track und eine IGC-Datei konvertiert
- **THEN** enthält die GPX-Datei zwei Tracks, zuerst den aus der GPX-Datei, dann den aus der IGC-Datei

### Requirement: Nachbearbeitung
Die App SHALL beim Konvertieren den GPS-Wochenüberlauf korrigieren. Enthält das zusammengeführte Ergebnis keine Tracks, aber Wegpunkte, SHALL die App die Wegpunkte zu einem Track machen.

#### Scenario: Nur Wegpunkte
- **WHEN** eine GPX-Datei nur 12 Wegpunkte enthält
- **THEN** enthält die erzeugte GPX-Datei einen Track mit diesen 12 Punkten

#### Scenario: Alter Logger mit Wochenüberlauf
- **WHEN** eine NMEA-Datei Zeiten enthält, die mehr als 512 Wochen vor dem heutigen Datum liegen
- **THEN** sind diese Zeiten in der GPX-Datei um 1024 Wochen verschoben

### Requirement: Fortschritt und Abbruch
Während der Konvertierung SHALL die App ein Fortschrittsfenster mit „Abbrechen“ zeigen und das Hauptfenster bedienbar lassen. Ein Abbruch SHALL die Konvertierung innerhalb einer Sekunde beenden, ohne Datei und ohne Fehlermeldung. Solange eine Konvertierung läuft, SHALL die App keine zweite starten.

#### Scenario: Große Datei abbrechen
- **WHEN** der Anwender während der Konvertierung einer 50-MB-NMEA-Datei „Abbrechen“ wählt
- **THEN** schließt sich das Fortschrittsfenster innerhalb einer Sekunde, und es erscheint weder ein Sicherungsdialog noch eine Fehlermeldung

#### Scenario: Zweite Konvertierung
- **WHEN** eine Konvertierung läuft und der Anwender weitere Dateien auf das Fenster zieht
- **THEN** nimmt die App sie nicht an, und der Menübefehl ist deaktiviert

### Requirement: Speichern
Nach erfolgreichem Lesen SHALL die App einen Sicherungsdialog zeigen und das Ergebnis als GPX 1.1 an den gewählten Ort schreiben (siehe `gpx-export`). Vorgeschlagen wird der Name der ersten konvertierten Datei mit der Endung `.gpx` und, sofern möglich, ihr Ordner.

#### Scenario: Name vorschlagen
- **WHEN** der Anwender `flug1.igc` und `flug2.igc` konvertiert
- **THEN** schlägt der Sicherungsdialog den Namen `flug1.gpx` vor

#### Scenario: Speichern abgebrochen
- **WHEN** der Anwender den Sicherungsdialog abbricht
- **THEN** wird keine Datei geschrieben und keine Meldung gezeigt

### Requirement: Fehler und Warnungen
Kann eine Datei nicht gelesen werden oder enthält sie keine verwertbaren Daten, SHALL die App die lokalisierte Meldung von GPSLoggerKit mit Dateinamen und, falls vorhanden, das technische Detail zeigen und nichts speichern. Hat der Import Warnungen erzeugt, SHALL die App sie nach dem Speichern zusammengefasst anzeigen, eine Zeile je Warnung.

#### Scenario: Kaputte GPX-Datei
- **WHEN** eine GPX-Datei in Zeile 12 nicht wohlgeformt ist
- **THEN** meldet die App, dass die Datei nicht wohlgeformt ist, nennt Datei und Zeile und zeigt keinen Sicherungsdialog

#### Scenario: Verworfene Sätze
- **WHEN** eine NMEA-Datei drei Sätze mit falscher Prüfsumme enthält
- **THEN** wird die GPX-Datei geschrieben, und danach meldet die App, dass in dieser Datei drei Datensätze mit falscher Prüfsumme übersprungen wurden

#### Scenario: Keine Positionen
- **WHEN** eine NMEA-Datei nur Sätze ohne gültigen Fix enthält
- **THEN** meldet die App, dass die Datei keine verwertbaren Daten enthält
