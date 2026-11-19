## MODIFIED Requirements

### Requirement: Support-Paket erstellen
Die App SHALL den Befehl „Support-Paket erstellen …“ im Menü „Hilfe“ anbieten. Die Fehlermeldung eines fehlgeschlagenen Lese- oder Löschvorgangs SHALL denselben Befehl als Knopf anbieten. Der Befehl SHALL die Inhalte des Pakets mit Häkchen zeigen, standardmäßig alle gewählt, und danach einen Sicherungsdialog mit dem Namen `myTracks-Loader-Support-<Datum>-<Uhrzeit>.zip` öffnen.

#### Scenario: Nach einem Fehler
- **WHEN** das Auslesen mit einer Zeitüberschreitung fehlschlägt und der Anwender in der Fehlermeldung „Support-Paket erstellen …“ wählt
- **THEN** zeigt die App die Inhaltsliste, und nach dem Sichern liegt ein ZIP mit dem Mitschnitt dieses Vorgangs vor

#### Scenario: Inhalt abgewählt
- **WHEN** der Anwender die Diagnose-Mitschnitte abwählt
- **THEN** enthält das ZIP keine Mitschnitte

#### Scenario: Vorgeschlagener Name
- **WHEN** der Anwender am 19. November 2026 um 14:05 ein Support-Paket erstellt
- **THEN** schlägt der Sicherungsdialog `myTracks-Loader-Support-20261119-1405.zip` vor

### Requirement: Inhalt des Support-Pakets
Das ZIP SHALL eine Übersichtsdatei mit der Liste der enthaltenen Teile enthalten und je nach Auswahl:
- System und App: App-Version und Build, macOS-Version, Mac-Modell, Architektur, Rosetta, Sprachen, Zeitzone
- das App-Protokoll und die Einstellungen der App
- serielle Anschlüsse und USB-Geräte mit Hersteller-ID, Produkt-ID und Namen, ohne Seriennummern
- gekoppelte Bluetooth-Geräte
- die gespeicherten Diagnose-Mitschnitte
- die Absturzberichte von myTracks Loader, auch solche, die noch unter dem alten Namen „gpsloader“ entstanden sind

#### Scenario: Vollständiges Paket
- **WHEN** der Anwender ein Paket mit allen Inhalten erstellt
- **THEN** enthält das ZIP die Übersichtsdatei, den Systembericht, das Protokoll, die Einstellungen, die Liste der Anschlüsse und USB-Geräte und alle gespeicherten Mitschnitte

#### Scenario: Keine Seriennummern
- **WHEN** ein USB-Gerät mit Seriennummer angeschlossen ist
- **THEN** erscheint die Seriennummer nicht im Paket

### Requirement: App-Protokoll
Die App SHALL ein Protokoll in `~/Library/Logs/myTracks Loader/` schreiben: App-Start mit Version und macOS-Version, Erscheinen und Verschwinden von Anschlüssen, Geräte- und Anschlusswahl, Beginn und Ergebnis jedes Vorgangs und jeder Konvertierung, Fehler mit Detailtext. Positionen und Dateinamen MUST NOT im Protokoll stehen. Das Protokoll SHALL rotieren und zusammen höchstens 5 MB belegen. Gibt es beim Start noch Protokoll- oder Mitschnitt-Ordner mit dem alten Namen „gpsloader“ und noch keine mit dem neuen Namen, SHALL die App sie unter den neuen Namen verschieben.

#### Scenario: Fehlgeschlagener Vorgang
- **WHEN** ein Auslesevorgang mit einem Protokollfehler endet
- **THEN** enthält das Protokoll Gerät, Anschluss, Ergebnis und Detailtext dieses Vorgangs mit Zeitstempel

#### Scenario: Rotation
- **WHEN** die Protokolldatei die Größengrenze überschreitet
- **THEN** beginnt eine neue Datei, und die ältesten Dateien werden gelöscht, sodass alle zusammen höchstens 5 MB belegen

#### Scenario: Ordner mit altem Namen
- **WHEN** die App startet und es `~/Library/Logs/gpsloader/` gibt, aber nicht `~/Library/Logs/myTracks Loader/`
- **THEN** liegt das bisherige Protokoll danach in `~/Library/Logs/myTracks Loader/`, und die App schreibt dort weiter

#### Scenario: Beide Ordner vorhanden
- **WHEN** die App startet und es beide Ordner gibt
- **THEN** lässt die App den alten Ordner unverändert und schreibt in den neuen
