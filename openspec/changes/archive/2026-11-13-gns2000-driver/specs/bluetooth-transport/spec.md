## Purpose

Verbindet gpsloader über IOBluetooth mit einem gekoppelten Bluetooth-Gerät, indem es den RFCOMM-Kanal eines benannten SDP-Dienstes öffnet. Das gilt für Logger, die nicht über `/dev/cu.*` laufen, etwa den GNS 2000.

## ADDED Requirements

### Requirement: Gerät und Dienst finden
Der Transport SHALL unter den gekoppelten Bluetooth-Geräten das erste mit einem der vorgegebenen Namen suchen. Eine bestehende Verbindung SHALL er schließen und neu aufbauen. Dann SHALL er per SDP-Abfrage den Dienst mit dem vorgegebenen Namen suchen und dessen RFCOMM-Kanal öffnen. Fehlt das Gerät, der Dienst oder der Kanal, MUST das Öffnen mit dem Fehler „Gerät nicht gefunden“ und einem Hinweis enden.

#### Scenario: Gerät nicht gekoppelt
- **WHEN** kein gekoppeltes Gerät „GNS 2000“ oder „GNS 2000 plus“ heißt
- **THEN** endet der Vorgang mit „Gerät nicht gefunden“ und dem Hinweis, das Gerät in den Systemeinstellungen zu koppeln

#### Scenario: Dienst fehlt
- **WHEN** das Gerät keinen Dienst „GNS GPS“ meldet
- **THEN** endet der Vorgang mit „Gerät nicht gefunden“, und der Detailtext nennt den gesuchten Dienst

### Requirement: Zeitlimits beim Verbinden
Verbindungsaufbau und SDP-Abfrage SHALL zusammen höchstens 20 Sekunden dauern, sonst MUST der Vorgang mit einer Zeitüberschreitung enden. Ein Abbruch durch den Anwender SHALL das Warten sofort beenden und die Verbindung schließen.

#### Scenario: Gerät ausgeschaltet
- **WHEN** das gekoppelte Gerät ausgeschaltet ist
- **THEN** endet der Vorgang spätestens nach 20 Sekunden mit einer Zeitüberschreitung

### Requirement: Daten übertragen
Der Transport SHALL die Schnittstelle `ByteTransport` erfüllen: Schreiben in Stücken bis zur MTU des Kanals sowie Lesen einer Anzahl Bytes oder bis zu einem Endezeichen, je mit Stille-Zeitlimit. Empfangene Daten SHALL er puffern, bis sie gelesen werden. Wird der Kanal vom Gerät geschlossen, MUST eine wartende Leseanforderung mit einem Fehler enden.

#### Scenario: Zeilen in mehreren Paketen
- **WHEN** eine Zeile in zwei RFCOMM-Paketen ankommt
- **THEN** liefert das Lesen bis CR LF die ganze Zeile

#### Scenario: Gerät trennt die Verbindung
- **WHEN** das Gerät den Kanal während des Lesens schließt
- **THEN** endet das Lesen mit einem Fehler statt mit einer Zeitüberschreitung

### Requirement: Schließen
Nach dem Vorgang SHALL der Transport den RFCOMM-Kanal und die Verbindung zum Gerät schließen, auch nach Fehlern und Abbruch. Mehrfaches Schließen MUST unschädlich sein.

#### Scenario: Abbruch beim Lesen
- **WHEN** der Anwender während des Auslesens abbricht
- **THEN** sind Kanal und Verbindung danach geschlossen

### Requirement: Bluetooth-Berechtigung
Die App SHALL eine Begründung für den Bluetooth-Zugriff (de/en) mitbringen, die macOS bei der ersten Nutzung anzeigt. Verweigert der Anwender den Zugriff, MUST der Vorgang mit „Gerät nicht gefunden“ und dem Hinweis auf die Datenschutz-Einstellungen enden.

#### Scenario: Zugriff verweigert
- **WHEN** der Anwender den Bluetooth-Zugriff für gpsloader verweigert hat
- **THEN** nennt die Fehlermeldung die Einstellung „Datenschutz & Sicherheit > Bluetooth“
