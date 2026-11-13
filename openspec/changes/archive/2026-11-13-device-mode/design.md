# Design: Direktmodus

## Context

- **LoggerCore** stellt bereit:
  - `LoggerDriver` (`read`, `erase`, `descriptor`, `resourceKey`) mit `DriverContext` (Fortschritt, Aktivität, Diagnose);
  - `LoggerSession` (Watchdog, Abbruch, Reservierung des Anschlusses);
  - `ByteTransport`.
- **SerialTransport** stellt `SerialPort` (Actor, exklusiv, Inaktivitäts-Timeouts, feste Baudrate) und `SerialPortCatalog` (Liste und Änderungen) bereit.
- **DiagnosticCapture** stellt `CapturingTransport` bereit.
- **App:** `SessionPresenter` übernimmt Lesen, Löschen, Bestätigung, Fortschrittsfenster und Speichern.
- **GPSLoggerKitGPL** hängt nur von GPSLoggerKit ab (Change `gpl-driver-package`). `LoggerCore` steht ihm deshalb nicht zur Verfügung.

## Goals / Non-Goals

**Goals:**
- Die Treiber des GPL-Pakets sind ohne Hardware testbar und laufen in der App mit allen vorhandenen Diensten der Sitzung.

**Non-Goals:**
- Ein allgemeiner Transport in GPSLoggerKit. Clean-Room-Treiber wie BG728 und GNS2000 entscheiden das in ihrem eigenen Change.

## Decisions

### D1 Schnittstelle im GPL-Paket

`Sources/GPSLoggerKitGPL/Device/DeviceProtocol.swift`, eigener Code:

```swift
public protocol DeviceConnection: Sendable {
    func write(_ bytes: [UInt8]) async throws
    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8]
    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8]
    func discardInput() async            // pending bytes
    func setBaudRate(_ rate: Int) async throws
}
public struct DeviceReporter: Sendable { progress(completed:total:), step(_:), activity() }
public struct DeviceProtocolError: Error { message }          // unexpected answer, unsupported device
public enum DeviceErase: Sendable { case unsupported, supported, experimental }
public protocol DeviceProtocol: Sendable {
    var eraseSupport: DeviceErase { get }
    func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording
    func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws
}
```

- **Fehler:** Zeitlimit und Abbruch kommen als Fehler der Verbindung und werden unverändert weitergereicht.
- **Alternative:** `ByteTransport` nach GPSLoggerKit verlegen. Verworfen für diesen Change, denn das wäre ein Umbau von LoggerCore samt Tests ohne Nutzen für die Portierungen.
- **Test-Helfer:** `SimulatedDevice` im Testziel des GPL-Pakets. Es ist ein Actor mit einer Antwortfunktion, die auf Geschriebenes reagiert und Bytes in einen Eingangspuffer legt. Zeitlimits laufen sofort ab, wenn nichts anliegt.

### D2 Anbindung in GPSLoaderKit

Neues Modul `DeviceDrivers`, abhängig von LoggerCore, SerialTransport, DiagnosticCapture und GPSLoggerKitGPL:
- **`DeviceEntry`:** Name, Treiber-Kennung, `connection` (`.serial(baud:)` oder `.hid`), Löschunterstützung und die Fabrik für das Protokoll mit den Optionen des Eintrags.
- **`DeviceCatalog.entries`:** Die Einträge kommen aus `DeviceCatalog.families`. Je Familie liefert der Port-Change seine Einträge. Dieser Change startet mit einer leeren Liste.
- **`ProtocolDriver: LoggerDriver`:**
  - Öffnet `SerialPort(path:baudRate:)` in `CapturingTransport` mit `context.diagnostics`, also exklusiv.
  - Reicht `ConnectionBridge` an das Protokoll weiter. Die Brücke setzt `DeviceConnection` auf `ByteTransport` um und gibt `setBaudRate` an `SerialPort` weiter.
  - Bildet `DeviceReporter` auf `context.progress` und `context.activity` ab.
  - Schließt in `defer`.
  - Bildet `DeviceProtocolError` auf `LoggerError(.protocolError, detail:)` ab.
- **HID:** Für Einträge mit `.hid` liefert der Port-Change von i-GotU eine Verbindungsfabrik. Bis dahin gibt es sie nicht.

### D3 Baudrate wechseln

`SerialPort.setBaudRate(_:)`: Prüfung gegen `supportedBaudRates`, dann `cfsetspeed` und `tcsetattr(TCSADRAIN)` auf den offenen Deskriptor. `baudRate` wird zur veränderlichen Eigenschaft des Actors. `discardInput` leert den internen Puffer und ruft `tcflush(TCIFLUSH)` auf.

### D4 Hauptfenster

- **`DevicePanel` (AppKit)** im Bereich „Gerät“:
  - `NSPopUpButton` Gerät, sortiert.
  - `NSPopUpButton` Anschluss mit USB-Name und Pfad.
  - Ein Hinweistext.
  - Die Knöpfe „Auslesen“ und „Speicher löschen …“.
- **Live-Aktualisierung:** über `SerialPortCatalog.changes()` in einer `Task` auf dem Main Actor.
- **Gemerkt** werden die Kennung des Geräts und der Pfad des Anschlusses unter `UserDefaults` `DeviceSelection`.
- **Gesperrt** sind die Knöpfe, solange `SessionPresenter.isRunning` gilt.
- **Leerer Katalog:** Ohne Einträge bleibt der bisherige Hinweis stehen.

### D5 Concurrency

- `ProtocolDriver` ist ein `Sendable`-Struct.
- `ConnectionBridge` hält nur `Sendable`-Referenzen (Transport, Port-Actor).
- Das Panel ist `@MainActor`.
- Abbruch: Die Sitzung bricht die Aufgabe ab, `SerialPort` reagiert innerhalb von 100 ms (`serial-transport`).

## Risks / Trade-offs

- **Zwei ähnliche Transport-Schnittstellen** (`ByteTransport`, `DeviceConnection`): → Die Brücke ist trivial. Zusammengelegt werden kann später, wenn GPSLoggerKit eigene Treiber bekommt.

## Migration Plan

Entfällt.
