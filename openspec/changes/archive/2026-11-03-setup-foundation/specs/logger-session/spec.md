# Spec Delta

## Purpose

Der einheitliche Ablauf eines Auslese- oder Löschvorgangs an einem GPS-Logger, unabhängig vom konkreten Treiber: Fortschritt, Abbruch, Zeitlimits, Fehlermeldungen, Bestätigung vor dem Löschen und Speichern des Ergebnisses als GPX.

## ADDED Requirements

### Requirement: Einheitlicher Treibervertrag
Jeder Treiber MUST über denselben Vertrag angesprochen werden. Er umfasst Auslesen, optional Löschen, die Angabe, ob Löschen unterstützt und ob es als experimentell eingestuft ist, sowie Fortschrittsmeldungen. Die Sitzung SHALL nur über diesen Vertrag mit Treibern arbeiten.

#### Scenario: Treiber ohne Löschfunktion
- **WHEN** ein Treiber angibt, dass er Löschen nicht unterstützt
- **THEN** bietet die Sitzung für dieses Gerät keine Löschaktion an

#### Scenario: Experimentelles Löschen
- **WHEN** ein Treiber Löschen als experimentell einstuft
- **THEN** weist die Sitzung vor der Bestätigung ausdrücklich darauf hin, dass das Löschen nicht mit einem echten Gerät getestet wurde

### Requirement: Fortschritt
Während eines Vorgangs SHALL die Sitzung den Fortschritt melden: bestimmt mit gelesenen und erwarteten Einheiten, sobald der Treiber die Gesamtmenge kennt, sonst unbestimmt.

#### Scenario: Bestimmter Fortschritt
- **WHEN** ein Treiber meldet, dass 250 von 1000 Punkten gelesen sind
- **THEN** zeigt die Sitzung einen Fortschritt von 25 %

#### Scenario: Unbestimmter Fortschritt
- **WHEN** ein Treiber keine Gesamtmenge kennt
- **THEN** zeigt die Sitzung einen unbestimmten Fortschritt mit der Beschreibung des aktuellen Schritts

### Requirement: Abbruch
Der Anwender MUST jeden laufenden Vorgang abbrechen können. Nach einem Abbruch SHALL die Sitzung alle Geräteverbindungen und gestarteten Prozesse innerhalb von 5 Sekunden freigeben. Teilergebnisse SHALL sie verwerfen.

#### Scenario: Abbruch beim Auslesen
- **WHEN** der Anwender während des Auslesens „Abbrechen“ wählt
- **THEN** endet der Vorgang mit dem Status „abgebrochen“
- **AND** es wird keine GPX-Datei geschrieben
- **AND** der serielle Port ist anschließend wieder frei

#### Scenario: Abbruch bei laufendem gpsbabel
- **WHEN** der Anwender abbricht, während ein gpsbabel-Prozess läuft
- **THEN** ist der gpsbabel-Prozess spätestens 5 Sekunden später beendet

### Requirement: Zeitlimit ohne Antwort
Erhält ein Vorgang über die vom Treiber festgelegte Zeit keine Daten vom Gerät, MUST die Sitzung ihn mit dem Fehler „Zeitüberschreitung“ beenden, statt unbegrenzt zu warten.

#### Scenario: Gerät antwortet nicht
- **WHEN** ein Gerät nach dem Öffnen der Verbindung keine Daten sendet
- **THEN** endet der Vorgang nach dem Zeitlimit mit dem Fehler „Zeitüberschreitung“ und einem Hinweis, Verbindung und Gerätewahl zu prüfen

### Requirement: Einheitliche Fehlermeldungen
Die Sitzung SHALL Fehler als verständliche, lokalisierte Meldung mit Fehlerart und technischem Detail ausgeben. Fehlerarten sind: Gerät nicht gefunden, Port belegt, Zeitüberschreitung, Protokollfehler, Rosetta fehlt, gpsbabel-Fehler, Schreibfehler, abgebrochen.

#### Scenario: Port belegt
- **WHEN** der gewählte serielle Port bereits von einem anderen Programm geöffnet ist
- **THEN** meldet die Sitzung „Port belegt“ mit dem Portnamen

#### Scenario: gpsbabel-Fehler
- **WHEN** gpsbabel mit einem Fehlercode endet
- **THEN** meldet die Sitzung „gpsbabel-Fehler“ und zeigt die Fehlerausgabe von gpsbabel als Detail

### Requirement: Ergebnis speichern
Nach erfolgreichem Auslesen SHALL die Sitzung das Ergebnis als GPX-Datei an einem vom Anwender gewählten Ort speichern. Der vorgeschlagene Dateiname MUST Gerätenamen sowie Datum und Uhrzeit des Auslesens enthalten.

#### Scenario: Erfolgreiches Auslesen
- **WHEN** ein Treiber einen Track mit 120 Punkten liefert
- **THEN** schlägt die Sitzung einen Dateinamen wie „Gerätename 2026-11-02 14-30.gpx“ vor
- **AND** schreibt nach Bestätigung eine GPX-Datei mit diesen 120 Punkten

#### Scenario: Keine Daten auf dem Gerät
- **WHEN** ein Treiber erfolgreich ausliest, aber keine Punkte und keine Wegpunkte liefert
- **THEN** meldet die Sitzung, dass der Logger keine Daten enthält, und schreibt keine Datei

### Requirement: Bestätigung vor dem Löschen
Die Sitzung MUST einen Löschvorgang nur nach einer ausdrücklichen Bestätigung des Anwenders starten. Der Bestätigungsdialog MUST darauf hinweisen, dass gelöschte Daten nicht wiederhergestellt werden können.

#### Scenario: Löschen abgelehnt
- **WHEN** der Anwender den Bestätigungsdialog für das Löschen abbricht
- **THEN** wird kein Befehl an das Gerät gesendet

#### Scenario: Löschen bestätigt
- **WHEN** der Anwender das Löschen bestätigt und der Treiber erfolgreich löscht
- **THEN** meldet die Sitzung, dass die Daten gelöscht wurden

### Requirement: Nur ein Vorgang gleichzeitig
Die App MUST verhindern, dass zwei Vorgänge gleichzeitig dasselbe Gerät oder denselben Port verwenden.

#### Scenario: Zweiter Start während laufendem Vorgang
- **WHEN** ein Vorgang läuft und der Anwender einen weiteren Vorgang für denselben Port starten will
- **THEN** wird der zweite Vorgang nicht gestartet und der Anwender erhält einen Hinweis
