## MODIFIED Requirements

### Requirement: Gerätekatalog
Der Gerätekatalog SHALL je Gerät den Namen, den Treiber, die Verbindungsart (seriell, USB-HID oder Bluetooth-RFCOMM), die Baudrate bzw. Gerätenamen und Dienst und die Löschunterstützung festlegen. Er SHALL nur Geräte enthalten, deren Treiber vorhanden ist.

#### Scenario: Treiber fehlt
- **WHEN** für eine Familie noch kein Treiber vorhanden ist
- **THEN** erscheinen ihre Geräte nicht in der Auswahl

#### Scenario: Bluetooth-Gerät
- **WHEN** der Anwender ein Gerät mit der Verbindungsart Bluetooth-RFCOMM wählt
- **THEN** entfällt die Anschlusswahl, und „Auslesen“ ist ohne Anschluss verfügbar

### Requirement: Anbindung der Treiber
Ein Treiber aus GPSLoggerKit oder GPSLoggerKitGPL SHALL über einen Adapter als Treiber der Sitzung laufen. Der Adapter SHALL den Anschluss bzw. das Gerät exklusiv öffnen und danach in jedem Fall schließen. Alle gesendeten und empfangenen Bytes SHALL er in den Diagnose-Mitschnitt schreiben und Fortschritt und Aktivität an die Sitzung melden. Protokollfehler des Treibers SHALL er als Protokollfehler mit Detailtext melden.

#### Scenario: Protokollfehler
- **WHEN** ein Treiber meldet, dass das Gerät eine unerwartete Antwort gesendet hat
- **THEN** zeigt die App die Meldung für Protokollfehler, und der Detailtext nennt die Antwort

#### Scenario: Mitschnitt
- **WHEN** ein Auslesevorgang mit einem simulierten Gerät endet
- **THEN** enthält der Diagnose-Mitschnitt alle gesendeten und empfangenen Bytes

#### Scenario: Mitschnitt über Bluetooth
- **WHEN** ein GNS 2000 bei eingeschaltetem Mitschnitt ausgelesen wird
- **THEN** enthält der Mitschnitt die über den RFCOMM-Kanal gesendeten und empfangenen Bytes
