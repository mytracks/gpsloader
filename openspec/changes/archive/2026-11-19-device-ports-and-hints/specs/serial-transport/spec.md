## ADDED Requirements

### Requirement: Art des Anschlusses
Das System SHALL zu jedem seriellen Anschluss angeben, ob er zu einem USB-Gerät, zu einem gekoppelten Bluetooth-Gerät oder zum System gehört. Systemanschlüsse sind `Bluetooth-Incoming-Port` und Anschlüsse ohne USB- und Bluetooth-Gerät, deren Name `debug` enthält.

#### Scenario: Gekoppeltes Bluetooth-Gerät
- **WHEN** ein gekoppelter Bluetooth-Logger den Anschluss `/dev/cu.HOLUX_M-241-SPPSlave` bereitstellt
- **THEN** ist der Anschluss als Bluetooth-Anschluss gekennzeichnet

#### Scenario: Systemanschluss
- **WHEN** die Anschlüsse `/dev/cu.Bluetooth-Incoming-Port` und `/dev/cu.debug-console` vorhanden sind
- **THEN** sind beide als Systemanschlüsse gekennzeichnet

### Requirement: USB-Geräte ermitteln
Das System SHALL alle angeschlossenen USB-Geräte mit Hersteller-ID, Produkt-ID und, soweit verfügbar, Hersteller- und Produktnamen auflisten. Seriennummern MUST NOT gelesen werden.

#### Scenario: Adapter ohne Treiber
- **WHEN** ein USB-Seriell-Adapter steckt, für den kein Treiber geladen ist
- **THEN** erscheint er in der Liste der USB-Geräte, obwohl es keinen Anschluss dazu gibt
