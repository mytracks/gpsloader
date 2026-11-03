# Spec Delta

## Purpose

Bereitstellung und Ausführung des mitgelieferten gpsbabel 1.7.0, über das alle gpsbabel-basierten Geräte und Dateiformate laufen. Dazu gehört die Erkennung von fehlendem Rosetta auf Apple Silicon samt Abhilfe.

## ADDED Requirements

### Requirement: Gebündeltes gpsbabel 1.7.0
Die App MUST genau gpsbabel 1.7.0 aus dem eigenen Bundle verwenden. Ein auf dem System installiertes gpsbabel oder eine andere Version SHALL sie nie verwenden.

#### Scenario: gpsbabel im System vorhanden
- **WHEN** auf dem Mac zusätzlich ein anderes gpsbabel im Suchpfad installiert ist
- **THEN** verwendet die App trotzdem das gpsbabel aus ihrem Bundle

#### Scenario: Versionsprüfung
- **WHEN** die App ihre gpsbabel-Laufzeit prüft
- **THEN** meldet das gebündelte gpsbabel die Version 1.7.0

### Requirement: Prüfung der Laufzeit
Die App SHALL beim Start und vor jedem gpsbabel-Vorgang prüfen, ob sich gpsbabel ausführen lässt. Das Ergebnis lautet: bereit, Rosetta fehlt oder defekt (mit Grund).

#### Scenario: Apple Silicon mit Rosetta
- **WHEN** die App auf einem Apple-Silicon-Mac mit installiertem Rosetta prüft
- **THEN** lautet das Ergebnis „bereit“

#### Scenario: Apple Silicon ohne Rosetta
- **WHEN** die App auf einem Apple-Silicon-Mac ohne Rosetta prüft
- **THEN** lautet das Ergebnis „Rosetta fehlt“

#### Scenario: Intel-Mac
- **WHEN** die App auf einem Intel-Mac prüft
- **THEN** lautet das Ergebnis „bereit“, ohne dass Rosetta eine Rolle spielt

#### Scenario: Beschädigtes Bundle
- **WHEN** das gpsbabel-Programm oder sein Qt-Framework im Bundle fehlt oder nicht geladen werden kann
- **THEN** lautet das Ergebnis „defekt“ mit dem technischen Grund

### Requirement: Rosetta-Installation anbieten
Fehlt Rosetta, SHALL die App verständlich erklären, wofür Rosetta gebraucht wird, und die Installation über den Systemdialog von macOS anbieten. Nach der Installation SHALL die App die Laufzeit erneut prüfen, ohne dass sie neu gestartet werden muss.

#### Scenario: Anwender installiert Rosetta
- **WHEN** der Anwender die angebotene Installation auslöst und im Systemdialog bestätigt
- **THEN** prüft die App nach Abschluss erneut und zeigt den Status „bereit“

#### Scenario: Anwender lehnt ab
- **WHEN** der Anwender die Installation ablehnt
- **THEN** bleibt der Status „Rosetta fehlt“
- **AND** native Funktionen der App bleiben nutzbar

### Requirement: Kein Start ohne Rosetta
Fehlt Rosetta, MUST die App einen gpsbabel-Vorgang mit dem Fehler „Rosetta fehlt“ ablehnen. Sie darf gpsbabel dann gar nicht erst starten.

#### Scenario: Auslesen über gpsbabel ohne Rosetta
- **WHEN** ein gpsbabel-basierter Vorgang gestartet wird und Rosetta fehlt
- **THEN** endet der Vorgang sofort mit dem Fehler „Rosetta fehlt“ und dem Installationsangebot

### Requirement: Sichere Ausführung
Die App MUST gpsbabel direkt als Prozess mit einer Liste einzelner Argumente starten. Den Aufruf über eine Shell darf sie nicht nutzen. Dateinamen und Gerätenamen mit Leerzeichen, Anführungszeichen oder Sonderzeichen MUST sie unverändert übergeben.

#### Scenario: Dateiname mit Sonderzeichen
- **WHEN** gpsbabel eine Eingabedatei namens `Tour "Süd" & Co; rm -rf.nmea` verarbeiten soll
- **THEN** erhält gpsbabel genau diesen Dateinamen als ein einzelnes Argument, und es wird kein weiteres Kommando ausgeführt

### Requirement: Ausgaben und Ergebnis erfassen
Die App SHALL die Standardausgabe, die Fehlerausgabe und den Exit-Code jedes gpsbabel-Aufrufs erfassen. Ein Exit-Code ungleich 0 MUST als gpsbabel-Fehler mit der Fehlerausgabe gemeldet werden.

#### Scenario: Erfolgreicher Aufruf
- **WHEN** gpsbabel mit Exit-Code 0 endet
- **THEN** gilt der Aufruf als erfolgreich, und die Ausgaben stehen dem Treiber zur Verfügung

#### Scenario: Fehlerhafter Aufruf
- **WHEN** gpsbabel mit einem Exit-Code ungleich 0 endet
- **THEN** wird ein gpsbabel-Fehler mit der vollständigen Fehlerausgabe gemeldet

### Requirement: Abbruch und Zeitlimit für gpsbabel
Wird ein Vorgang abgebrochen oder überschreitet ein gpsbabel-Aufruf sein Zeitlimit, MUST die App den gpsbabel-Prozess beenden: zuerst regulär, nach 3 Sekunden erzwungen. Es dürfen keine verwaisten gpsbabel-Prozesse zurückbleiben, auch nicht beim Beenden der App.

#### Scenario: Abbruch
- **WHEN** ein laufender gpsbabel-Aufruf abgebrochen wird
- **THEN** ist der Prozess nach spätestens 3 Sekunden beendet

#### Scenario: App wird während eines Aufrufs beendet
- **WHEN** der Anwender die App beendet, während gpsbabel läuft
- **THEN** wird der gpsbabel-Prozess beendet, bevor die App endet

### Requirement: Arbeitsverzeichnis
Die App SHALL jeden gpsbabel-Aufruf in einem eigenen, leeren temporären Arbeitsverzeichnis ausführen. Nach dem Vorgang SHALL sie es entfernen, damit Nebenprodukte wie Rohdaten-Dateien keine späteren Aufrufe beeinflussen.

#### Scenario: Nebenprodukt im Arbeitsverzeichnis
- **WHEN** gpsbabel beim Auslesen eine Datei `data.bin` im Arbeitsverzeichnis anlegt
- **THEN** steht sie dem Treiber nach dem Aufruf zur Verfügung
- **AND** ist nach Ende des Vorgangs gelöscht
