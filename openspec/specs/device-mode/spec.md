# device-mode Specification

## Purpose
Der Direktmodus von gpsloader: Gerät und Anschluss im Hauptfenster wählen, Auslesen und Löschen starten, der Gerätekatalog aller nativen Treiber und ihre Anbindung an die Sitzung, über serielle Schnittstelle oder USB-HID.

## Requirements

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

### Requirement: Korrektur des GPS-Wochenüberlaufs beim Auslesen
Der Adapter der Treiber SHALL auf jedes ausgelesene Ergebnis die Korrektur des GPS-Wochenüberlaufs der Spec `logger-kit` anwenden, mit dem Zeitpunkt des Auslesens als Bezug, für Trackpunkte und Wegpunkte. Die Korrektur SHALL immer aktiv sein. Ein Treiber, der Tracks nach Zeiten teilt oder benennt, SHALL dafür die korrigierten Zeiten verwenden.

#### Scenario: Logger mit Wochenüberlauf
- **WHEN** ein simuliertes Gerät am 13. November 2026 einen Punkt mit der Zeit 2. November 2026 minus 1024 Wochen liefert
- **THEN** hat der Punkt im Ergebnis die Zeit 2. November 2026

#### Scenario: Aktuelle Zeiten bleiben
- **WHEN** ein simuliertes Gerät einen Punkt liefert, der weniger als 512 Wochen vor dem Auslesen liegt
- **THEN** ist seine Zeit im Ergebnis unverändert

#### Scenario: Tracknamen nach der Korrektur
- **WHEN** ein GNS 2000 Punkte liefert, deren Zeiten um 1024 Wochen zu früh liegen
- **THEN** tragen die Tracks die Namen der korrigierten Zeiten, und es entsteht keine zusätzliche Trackgrenze
