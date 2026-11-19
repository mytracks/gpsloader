# support-package Specification

## Purpose
Bündelt alles, was der Entwickler zur Analyse eines Fehlers bei einem Anwender braucht, in ein ZIP, das der Anwender selbst verschickt: System- und App-Informationen, App-Protokoll, Anschlüsse, Geräte und Diagnose-Mitschnitte.

## Requirements

### Requirement: Support-Paket erstellen
Die App SHALL den Befehl „Support-Paket erstellen …“ im Menü „Hilfe“ anbieten. Die Fehlermeldung eines fehlgeschlagenen Lese- oder Löschvorgangs SHALL denselben Befehl als Knopf anbieten. Der Befehl SHALL die Inhalte des Pakets mit Häkchen zeigen, standardmäßig alle gewählt, und danach einen Sicherungsdialog mit dem Namen `gpsloader-support-<Datum>-<Uhrzeit>.zip` öffnen.

#### Scenario: Nach einem Fehler
- **WHEN** das Auslesen mit einer Zeitüberschreitung fehlschlägt und der Anwender in der Fehlermeldung „Support-Paket erstellen …“ wählt
- **THEN** zeigt die App die Inhaltsliste, und nach dem Sichern liegt ein ZIP mit dem Mitschnitt dieses Vorgangs vor

#### Scenario: Inhalt abgewählt
- **WHEN** der Anwender die Diagnose-Mitschnitte abwählt
- **THEN** enthält das ZIP keine Mitschnitte

### Requirement: Inhalt des Support-Pakets
Das ZIP SHALL eine Übersichtsdatei mit der Liste der enthaltenen Teile enthalten und je nach Auswahl:
- System und App: App-Version und Build, macOS-Version, Mac-Modell, Architektur, Rosetta, Sprachen, Zeitzone
- das App-Protokoll und die Einstellungen der App
- serielle Anschlüsse und USB-Geräte mit Hersteller-ID, Produkt-ID und Namen, ohne Seriennummern
- gekoppelte Bluetooth-Geräte
- die gespeicherten Diagnose-Mitschnitte
- die Absturzberichte von gpsloader

#### Scenario: Vollständiges Paket
- **WHEN** der Anwender ein Paket mit allen Inhalten erstellt
- **THEN** enthält das ZIP die Übersichtsdatei, den Systembericht, das Protokoll, die Einstellungen, die Liste der Anschlüsse und USB-Geräte und alle gespeicherten Mitschnitte

#### Scenario: Keine Seriennummern
- **WHEN** ein USB-Gerät mit Seriennummer angeschlossen ist
- **THEN** erscheint die Seriennummer nicht im Paket

### Requirement: Datenschutz im Support-Paket
Die Inhaltsliste MUST darauf hinweisen, dass Diagnose-Mitschnitte Positionsdaten enthalten. Das Paket MUST nur lokal gesichert werden; die App MUST es weder versenden noch hochladen. Die Liste der Bluetooth-Geräte SHALL nur angeboten werden, wenn die App die Bluetooth-Berechtigung bereits hat; das Erstellen des Pakets MUST keinen Berechtigungsdialog auslösen.

#### Scenario: Ohne Bluetooth-Berechtigung
- **WHEN** die App noch keine Bluetooth-Berechtigung hat und der Anwender ein Paket erstellt
- **THEN** erscheint kein Berechtigungsdialog, und die Inhaltsliste nennt die Bluetooth-Geräte als nicht verfügbar

### Requirement: App-Protokoll
Die App SHALL ein Protokoll in `~/Library/Logs/gpsloader/` schreiben: App-Start mit Version und macOS-Version, Erscheinen und Verschwinden von Anschlüssen, Geräte- und Anschlusswahl, Beginn und Ergebnis jedes Vorgangs und jeder Konvertierung, Fehler mit Detailtext. Positionen und Dateinamen MUST NOT im Protokoll stehen. Das Protokoll SHALL rotieren und zusammen höchstens 5 MB belegen.

#### Scenario: Fehlgeschlagener Vorgang
- **WHEN** ein Auslesevorgang mit einem Protokollfehler endet
- **THEN** enthält das Protokoll Gerät, Anschluss, Ergebnis und Detailtext dieses Vorgangs mit Zeitstempel

#### Scenario: Rotation
- **WHEN** die Protokolldatei die Größengrenze überschreitet
- **THEN** beginnt eine neue Datei, und die ältesten Dateien werden gelöscht, sodass alle zusammen höchstens 5 MB belegen
