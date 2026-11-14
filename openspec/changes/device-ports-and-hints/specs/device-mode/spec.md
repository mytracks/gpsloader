## MODIFIED Requirements

### Requirement: Anschluss wählen
Für Geräte mit serieller Verbindung SHALL das Fenster die vorhandenen Anschlüsse `/dev/cu.*` mit sprechenden Namen anbieten: USB-Anschlüsse mit Produktname oder Chip-Hersteller, Bluetooth-Anschlüsse als „Bluetooth:“ mit Gerätenamen, den Pfad als Tooltip. Systemanschlüsse SHALL ausgeblendet sein. Passt der Name eines Anschlusses zum gewählten Gerät, SHALL er oben stehen und vorausgewählt sein, danach USB-, dann Bluetooth-Anschlüsse. Die Liste SHALL sich bei An- und Abstecken aktualisieren. Ohne seriellen Anschluss SHALL die Wahl entfallen; fehlt ein Anschluss, SHALL das Fenster darauf hinweisen und das Auslesen nicht anbieten.

#### Scenario: Logger angesteckt
- **WHEN** der Anwender bei geöffnetem Fenster einen USB-Logger ansteckt
- **THEN** erscheint sein Anschluss in der Liste

#### Scenario: Kein Anschluss
- **WHEN** ein serielles Gerät gewählt ist und kein Anschluss vorhanden ist
- **THEN** ist „Auslesen“ deaktiviert, und ein Hinweis nennt den Grund

#### Scenario: Passender Bluetooth-Anschluss
- **WHEN** „Holux M-241“ gewählt ist und die Anschlüsse `/dev/cu.usbserial-1410` und `/dev/cu.HOLUX_M-241-SPPSlave` vorhanden sind
- **THEN** steht „Bluetooth: HOLUX_M-241-SPPSlave“ oben und ist vorausgewählt

#### Scenario: Systemanschlüsse
- **WHEN** nur `/dev/cu.Bluetooth-Incoming-Port` und `/dev/cu.debug-console` vorhanden sind
- **THEN** ist die Liste leer, und der Hinweis „kein Anschluss“ erscheint

## ADDED Requirements

### Requirement: Hinweise zum Gerät
Der Gerätekatalog SHALL je Gerät Hinweise mit Bedingung festlegen können: immer oder bei gewähltem Bluetooth-Anschluss. Das Fenster SHALL die zutreffenden Hinweise unter der Anschlusswahl zeigen. Ein Hinweis mit Bedingung SHALL auch in der Fehlermeldung eines fehlgeschlagenen Lesevorgangs erscheinen, etwa bei Zeitüberschreitung oder unerwarteter Antwort.

#### Scenario: M-241 über Bluetooth
- **WHEN** „Holux M-241“ und ein Bluetooth-Anschluss gewählt sind
- **THEN** rät ein Hinweis, den Logger über USB zu verbinden

#### Scenario: Fehlschlag über Bluetooth
- **WHEN** das Auslesen des M-241 über einen Bluetooth-Anschluss scheitert, weil das Gerät nicht oder unerwartet antwortet
- **THEN** nennt die Fehlermeldung denselben Hinweis

### Requirement: Fehlender Treiber
Ist ein serielles Gerät gewählt und steckt ein USB-Gerät mit der Hersteller-ID eines bekannten USB-Seriell-Chips (Silicon Labs, Prolific, FTDI, WCH), zu dem kein Anschluss existiert, SHALL das Fenster auf den vermutlich fehlenden Treiber hinweisen und die Treiberseite des Herstellers verlinken.

#### Scenario: Treiber fehlt
- **WHEN** ein serielles Gerät gewählt ist und ein USB-Gerät mit der Hersteller-ID von Prolific (0x067B) steckt, aber kein Anschluss dazu existiert
- **THEN** nennt ein Hinweis den fehlenden Prolific-Treiber und verlinkt die Treiberseite

#### Scenario: Treiber vorhanden
- **WHEN** zu dem USB-Gerät ein Anschluss existiert
- **THEN** erscheint kein Hinweis auf einen fehlenden Treiber
