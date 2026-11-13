## ADDED Requirements

### Requirement: Gerät wählen
Das Hauptfenster SHALL im Bereich „Gerät“ eine Auswahl aller Geräte des Gerätekatalogs anbieten, alphabetisch sortiert. Die zuletzt gewählte Kombination aus Gerät und Anschluss SHALL beim nächsten Start vorausgewählt sein, sofern beide noch vorhanden sind.

#### Scenario: Auswahl merken
- **WHEN** der Anwender „Qstarz BT-Q1000“ und `/dev/cu.usbserial-1410` wählt und die App neu startet
- **THEN** sind Gerät und Anschluss wieder ausgewählt, sofern der Anschluss vorhanden ist

### Requirement: Anschluss wählen
Für Geräte mit serieller Verbindung SHALL das Fenster die vorhandenen Anschlüsse `/dev/cu.*` mit ihren USB-Namen anbieten und die Liste bei An- und Abstecken ohne Neustart aktualisieren. Für Geräte ohne seriellen Anschluss SHALL die Anschlusswahl entfallen. Ist kein passender Anschluss vorhanden, SHALL das Fenster darauf hinweisen und das Auslesen nicht anbieten.

#### Scenario: Logger angesteckt
- **WHEN** der Anwender bei geöffnetem Fenster einen USB-Logger ansteckt
- **THEN** erscheint sein Anschluss in der Liste

#### Scenario: Kein Anschluss
- **WHEN** ein serielles Gerät gewählt ist und kein Anschluss vorhanden ist
- **THEN** ist „Auslesen“ deaktiviert, und ein Hinweis nennt den Grund

### Requirement: Auslesen und Löschen starten
„Auslesen“ SHALL den Treiber des gewählten Geräts mit dem gewählten Anschluss über die Sitzung (`logger-session`) starten. „Speicher löschen …“ SHALL nur für Geräte angeboten werden, deren Treiber löschen kann, und SHALL vorher die Bestätigung der Sitzung einholen. Während eines Vorgangs SHALL keiner der beiden Knöpfe einen zweiten Vorgang starten.

#### Scenario: Gerät ohne Löschfunktion
- **WHEN** ein Gerät gewählt ist, dessen Treiber nicht löschen kann
- **THEN** ist „Speicher löschen …“ nicht verfügbar

### Requirement: Gerätekatalog
Der Gerätekatalog SHALL je Gerät den Namen, den Treiber, die Verbindungsart (seriell oder USB-HID), die Baudrate und die Löschunterstützung festlegen. Er SHALL nur Geräte enthalten, deren Treiber vorhanden ist.

#### Scenario: Treiber fehlt
- **WHEN** für eine Familie noch kein Treiber vorhanden ist
- **THEN** erscheinen ihre Geräte nicht in der Auswahl

### Requirement: Anbindung der Treiber
Ein Treiber aus GPSLoggerKitGPL SHALL über einen Adapter als Treiber der Sitzung laufen. Der Adapter SHALL den Anschluss exklusiv öffnen und danach in jedem Fall schließen. Alle gesendeten und empfangenen Bytes SHALL er in den Diagnose-Mitschnitt schreiben und Fortschritt und Aktivität an die Sitzung melden. Protokollfehler des Treibers SHALL er als Protokollfehler mit Detailtext melden.

#### Scenario: Protokollfehler
- **WHEN** ein Treiber meldet, dass das Gerät eine unerwartete Antwort gesendet hat
- **THEN** zeigt die App die Meldung für Protokollfehler, und der Detailtext nennt die Antwort

#### Scenario: Mitschnitt
- **WHEN** ein Auslesevorgang mit einem simulierten Gerät endet
- **THEN** enthält der Diagnose-Mitschnitt alle gesendeten und empfangenen Bytes
