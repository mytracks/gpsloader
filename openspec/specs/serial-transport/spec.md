# serial-transport Specification

## Purpose
Byteweise Kommunikation mit GPS-Loggern über serielle Ports (`/dev/cu.*`), wie sie USB-Seriell-Adapter und gekoppelte Bluetooth-Geräte bereitstellen. Die Kommunikation hat feste Zeitlimits und lässt sich jederzeit abbrechen.

## Requirements

### Requirement: Ports ermitteln
Das System SHALL alle aktuell vorhandenen seriellen Ports `/dev/cu.*` auflisten. Für USB-Geräte SHALL es, soweit verfügbar, Hersteller-ID, Produkt-ID und Produktnamen mitliefern.

#### Scenario: USB-Seriell-Adapter angeschlossen
- **WHEN** ein Logger mit einem CP210x-Adapter angeschlossen ist
- **THEN** enthält die Liste den Port (z. B. `/dev/cu.SLAB_USBtoUART`) mit Hersteller- und Produkt-ID

#### Scenario: Gekoppeltes Bluetooth-Gerät
- **WHEN** ein gekoppelter Bluetooth-Logger einen Port `/dev/cu.<Name>` bereitstellt
- **THEN** enthält die Liste diesen Port ohne USB-Angaben

### Requirement: Port-Änderungen erkennen
Das System SHALL melden, wenn serielle Ports hinzukommen oder verschwinden, damit die UI die Liste ohne Neustart aktualisieren kann.

#### Scenario: Gerät wird eingesteckt
- **WHEN** während die App läuft ein USB-Seriell-Gerät eingesteckt wird
- **THEN** wird ein neuer Port gemeldet

### Requirement: Port öffnen und konfigurieren
Das System SHALL einen Port exklusiv öffnen können, mit einer angegebenen Baudrate (mindestens 4800, 9600, 19200, 38400, 57600, 115200), 8 Datenbits, ohne Parität, 1 Stoppbit, ohne Flusskontrolle und im Rohmodus.

#### Scenario: Öffnen mit 115200 Baud
- **WHEN** ein Treiber einen vorhandenen Port mit 115200 Baud anfordert
- **THEN** ist der Port mit 115200 8N1 im Rohmodus geöffnet

#### Scenario: Port existiert nicht
- **WHEN** ein Treiber einen nicht vorhandenen Port öffnen will
- **THEN** schlägt das Öffnen mit dem Fehler „Gerät nicht gefunden“ fehl

#### Scenario: Port bereits geöffnet
- **WHEN** ein Port exklusiv von einem anderen Prozess geöffnet ist
- **THEN** schlägt das Öffnen mit dem Fehler „Port belegt“ fehl

### Requirement: Lesen mit Zeitlimit
Das System SHALL Lesevorgänge mit Zeitlimit anbieten: eine bestimmte Anzahl Bytes oder alles bis zu einer Endmarkierung (z. B. `\r\n`). Läuft das Zeitlimit ohne vollständige Daten ab, MUST der Lesevorgang mit „Zeitüberschreitung“ enden.

#### Scenario: Zeile lesen
- **WHEN** das Gerät `$TEST,1,2\r\n` sendet und eine Zeile bis `\r\n` angefordert ist
- **THEN** liefert der Lesevorgang die Zeile ohne die Endmarkierung

#### Scenario: Daten in Teilstücken
- **WHEN** 4096 Bytes angefordert sind und das Gerät sie in mehreren Teilstücken sendet
- **THEN** liefert der Lesevorgang erst nach allen 4096 Bytes

#### Scenario: Gerät schweigt
- **WHEN** innerhalb des Zeitlimits keine Daten eintreffen
- **THEN** endet der Lesevorgang mit „Zeitüberschreitung“

### Requirement: Schreiben
Das System SHALL Bytefolgen vollständig an das Gerät senden. Ein Schreibfehler MUST als Fehler gemeldet werden.

#### Scenario: Befehl senden
- **WHEN** ein Treiber 16 Bytes sendet
- **THEN** werden alle 16 Bytes an den Port übergeben

### Requirement: Abbruch und Freigabe
Das System MUST einen laufenden Lese- oder Schreibvorgang bei einem Abbruch sofort beenden. Den Port SHALL es in jedem Fall freigeben: bei Erfolg, bei Fehler und bei Abbruch.

#### Scenario: Abbruch während des Lesens
- **WHEN** ein Lesevorgang auf Daten wartet und abgebrochen wird
- **THEN** endet der Lesevorgang mit „abgebrochen“ und der Port ist geschlossen

#### Scenario: Gerät wird abgezogen
- **WHEN** das Gerät während der Kommunikation entfernt wird
- **THEN** endet der laufende Vorgang mit einem Fehler und der Port ist freigegeben

### Requirement: Austauschbarer Transport
Treiber MUST über eine Transport-Abstraktion kommunizieren. So lässt sich derselbe Treiber ohne Hardware gegen einen vorgegebenen oder aufgezeichneten Gerätedialog testen.

#### Scenario: Treiber gegen Mock-Transport
- **WHEN** ein Treiber mit einem Mock-Transport ausgeführt wird, der auf einen erwarteten Befehl eine vorgegebene Antwort liefert
- **THEN** verhält sich der Treiber so, als wäre ein echtes Gerät angeschlossen

#### Scenario: Unerwarteter Befehl im Mock
- **WHEN** ein Treiber einen Befehl sendet, den der Mock-Transport nicht erwartet
- **THEN** schlägt der Test mit einer Meldung fehl, die erwarteten und tatsächlichen Befehl nennt
