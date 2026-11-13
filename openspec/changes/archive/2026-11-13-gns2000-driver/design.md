# Design: GNS 2000 über Bluetooth

## Context

- **Alt-App:** Sie las den GNS 2000 mit dem internen Treiber `*GNS2000`, im Gerätekatalog ohne Anschlusswahl (`driverurl` „skip“).
  - Code: `input/mytracks4mac/DsTrackFramework/Source/Classes/GpsDriver/GNS2000.m` und `GNS2000.h`, Stand des myTracks-Repositorys `9245389`.
  - Analyse: `docs/legacy-analysis.md`, Abschnitt `*GNS2000`.
  - Bekannte Schwäche (Abschnitt 8): Ohne Zeitlimit kann der Treiber hängen bleiben.
- **Bestand in gpsloader:**
  - Die Geräteschnittstelle (`DeviceConnection`, `DeviceProtocol`) liegt in `Packages/GPSLoggerKitGPL/Sources/GPSLoggerKitGPL/Device/DeviceProtocol.swift`.
  - Der Adapter `ProtocolDriver` und der Katalog liegen in `GPSLoaderKit/DeviceDrivers`.
  - Vorbild für einen Transport ohne Port ist das Modul `HIDTransport` (i-GotU).
  - Der serielle Weg nutzt `CapturingTransport` und `ConnectionBridge` für Mitschnitt und Aktivität.
- **Hardware:** Der Entwickler hat keinen GNS 2000 und auch sonst keine Bluetooth-Logger.

## Goals / Non-Goals

**Goals:**
- Lesen und Löschen wie die Alt-App, aber mit Zeitlimits, Fortschritt und Abbruch.
- Treiberlogik unter MIT in GPSLoggerKit, ohne Hardware testbar.
- Ein Bluetooth-Transport, der sich wie die anderen Transporte in Mitschnitt und Sitzung einfügt.

**Non-Goals:**
- Koppeln aus der App, Versionsabfrage, Ortszeit im Track-Namen.
- Bluetooth unter iOS.

## Decisions

### D1 Grundlagen

- **Eigener Code:** `GNS2000.m` (© 2013 Dirk Stichling) ist die einzige Grundlage. Neu geschrieben werden, nicht übersetzt:
  - `calculateChecksum` und `sendCommand` (Zeilen 216–242);
  - `splitResponse` (244–288);
  - die Befehle `PGNS,R` und `PGNS,C` (295–304);
  - `processResponse`, `processPMTKLOX` (320–456) und `readData` (458–509);
  - die Abläufe in `importTracksFromDevice` und `deleteTracksFromDevice` (535–613);
  - Verbindung und SDP aus `connect` und `openGPSChannel` (71–149), umgesetzt im Transport (D4).
- **Clean-Room:** Kein GPL-Quelltext wird gelesen, auch nicht gpsbabels LOCUS-Code. `PROVENANCE.md` von GPSLoggerKit nennt die Grundlage.

### D2 Geräteschnittstelle nach GPSLoggerKit

- **Umzug:** `Device/DeviceProtocol.swift` wandert von GPSLoggerKitGPL nach `GPSLoggerKit/Sources/GPSLoggerKit/Device/DeviceProtocol.swift`.
  - Dateikopf wie bei GPSLoggerKit üblich: MIT, eigener Code, kein SPDX-GPL.
  - Die öffentlichen Namen bleiben gleich: `DeviceConnection`, `DeviceReporter`, `DeviceProtocolError`, `DeviceErase`, `DeviceProtocol`.
- **Folgen im GPL-Paket:** Es importiert `GPSLoggerKit` bereits überall, die Treiber übersetzen also ohne Änderung. Die interne Hilfe `readLine` wird nirgends benutzt und entfällt.
- **Folgen in GPSLoaderKit:** `DeviceDrivers` und `HIDTransport` beziehen die Typen über `import GPSLoggerKit`, die Abhängigkeit besteht schon.
- **Simulation:** Das Test-Hilfsmittel `SimulatedDevice` bleibt im GPL-Paket. GPSLoggerKit bekommt eine eigene Kopie, denn Testziele zweier Pakete können keinen Code teilen.
- **Concurrency:** unverändert. Die Typen sind `Sendable`, `DeviceConnection` ist ein `Sendable`-Protokoll mit async-Methoden.

### D3 Treiber `GNS2000Device`

Ort: `GPSLoggerKit/Sources/GPSLoggerKit/Devices/GNS2000/GNS2000Device.swift`.

1. **Bereitschaft:** Zeilen bis CR LF lesen, bis eine mit `$` beginnt. Das Zeitlimit beträgt 10 Sekunden für die ganze Wartezeit; die Alt-App wartete ohne Zeitlimit.
2. **Lesen:**
   - `$PGNS,R*xx` senden (Prüfsumme in Kleinbuchstaben wie `calculateChecksum`).
   - Dann Zeilen lesen, mit 10 Sekunden Zeitlimit je Zeile: `$PMTKLOX,0,n` setzt die Paketzahl, `$PMTKLOX,1,i,w…` liefert Datensätze, `$PMTKLOX,2` beendet.
   - Fortschritt: `reporter.progress(gelesenePakete, of: n)`.
   - Zeilen mit falscher oder fehlender Prüfsumme werden übersprungen, wie bei `splitResponse`.
   - Andere Sätze, z. B. laufendes NMEA, werden ignoriert.
3. **Datensätze:** Je vier Wörter ergeben 16 Bytes in Textreihenfolge. Ungültige Hex-Zeichen machen den Datensatz ungültig.
   - Gelesen werden UInt32 LE (Zeit), UInt8 (Fix), Float32 LE (Breite, Länge) und Int16 LE (Höhe).
   - Verworfen werden Datensätze aus lauter `FF` und solche mit einem Fix außerhalb von 1 bis 4.
   - Byte 15 wird wie in der Alt-App nicht ausgewertet. Ob es eine Prüfsumme ist, zeigt erst der Test mit dem Gerät.
4. **Tracks:**
   - Ein neuer Track beginnt, wenn ein Zeitstempel kleiner ist als der vorige. Die Alt-App verglich nur mit dem vorigen *gültigen* Punkt; das übernimmt der Port.
   - Name: erste Punktzeit als `yyyy-MM-dd HH:mm` in UTC, über einen `DateFormatter` mit `en_US_POSIX` und UTC.
5. **Löschen:**
   - `$PGNS,C*xx` senden und Zeilen lesen, bis `$PMTK001` kommt; wie in der Alt-App wird jedes `$PMTK001` als Bestätigung gewertet.
   - Ein Zähler erfasst Zeilen in Folge, die nicht mit `$P` beginnen. Bei 11 wird der Befehl erneut gesendet und der Zähler zurückgesetzt, höchstens fünf Sendungen insgesamt.
   - Danach endet der Vorgang mit dem `DeviceProtocolError` „The GNS 2000 did not confirm erasing“.
   - Die Alt-App sendete nach Überschreiten der 10 bei jeder weiteren Zeile erneut, ohne Obergrenze.
6. **Löschunterstützung:** `.supported`. Der Ablauf lief jahrelang in myTracks.
7. **Concurrency:** `GNS2000Device` ist ein zustandsloser `Sendable`-Wertetyp; Zustand gibt es nur lokal in `read`/`erase`. Abbruch wirkt über die Lesefunktionen der Verbindung.

### D4 Modul `BluetoothTransport` (GPSLoaderKit, nur macOS)

- **`RFCOMMTransport`:** eine `final class`, `@unchecked Sendable`, die `ByteTransport` erfüllt.
  - **Isolation:** IOBluetooth ruft seine Delegates auf dem Main-Run-Loop auf. Deshalb laufen alle IOBluetooth-Aufrufe in `MainActor.run`.
  - **Daten:** Empfangene Daten landen in einem gesperrten Puffer (Muster `HIDInputBuffer`). Lesende warten mit Stille-Zeitlimit auf neue Daten über eine Benachrichtigung (`AsyncStream` je Leser oder Polling im 10-ms-Takt wie beim HID-Transport). Die Wahl fällt bei der Umsetzung nach dem Vorbild `HIDDeviceConnection`.
  - **Öffnen:**
    1. In `IOBluetoothDevice.pairedDevices()` das erste Gerät mit passendem Namen suchen.
    2. Ist es verbunden: `closeConnection()`. Dann `openConnection()`.
    3. `performSDPQuery(_:)` und auf `sdpQueryComplete` warten.
    4. In `services` den Dienst mit `getServiceName() == serviceName` suchen, `getRFCOMMChannelID`, dann `openRFCOMMChannelSync(_:withChannelID:delegate:)`.

    Das Ganze hat ein Zeitlimit von 20 Sekunden. Die festen Wartezeiten von 2 Sekunden aus der Alt-App entfallen.
  - **Schreiben:** `writeSync` in Stücken bis `getMTU()`.
  - **Schließen:** `rfcommChannelClosed` beendet wartende Leser mit `LoggerError(.deviceNotFound, detail: "Bluetooth connection closed")`. `close()` schließt Kanal und Verbindung.
  - **Fehler:** Für „nicht gefunden“, „Dienst fehlt“ und „Zugriff verweigert“ gibt es `LoggerError(.deviceNotFound)` mit Detail und Hinweis. Ist die Zustimmung verweigert (`CBManager.authorization == .denied`, ab macOS 10.15 lesbar), nennt die Meldung „Datenschutz & Sicherheit > Bluetooth“.
- **Fabrik:** `IOBluetoothTransportFactory: BluetoothTransportFactory` erzeugt den Transport für einen Katalogeintrag. Schlüssel für die Reservierung: `bluetooth:<erster Gerätename>`.

### D5 Katalog und Adapter

- **Verbindungsart:** `DeviceConnectionKind.bluetooth(deviceNames: [String], serviceName: String)`; `needsPort` ist `false`.
- **Fabrik-Protokoll in `DeviceDrivers`:** `BluetoothTransportFactory` mit `resourceKey(for:)` und `makeTransport(for:) -> any ByteTransport`.
- **`ProtocolDriver`:** bekommt `bluetoothFactory`.
  - Fall `.bluetooth`: Transport erzeugen, in `CapturingTransport` hüllen und öffnen, dann `ConnectionBridge` wie im seriellen Fall. So landen alle Bytes im Mitschnitt.
  - `setBaudRate` und `discardInput` wirken nur auf `SerialPort`. Für RFCOMM ist `discardInput` nicht nötig, der Treiber nutzt es nicht.
- **Katalog:** `Families/GNS2000Devices.swift` mit Eintrag `gns2000.gns-2000`, Name „GNS 2000“, Namen `["GNS 2000", "GNS 2000 plus"]` und Dienst „GNS GPS“.
- **App:** `MainWindowController` setzt `devicePanel.bluetoothFactory = IOBluetoothTransportFactory()`. `DevicePanel` reicht die Fabrik an `ProtocolDriver` weiter, wie `hidFactory`.

### D6 Berechtigung

- **Info.plist:** `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` in `project.yml`, übersetzt über `App/InfoPlist.xcstrings` (de/en): „gpsloader verbindet sich über Bluetooth mit GPS-Loggern wie dem GNS 2000, um ihre Aufzeichnungen zu lesen.“
- **Entitlements:** keine. Die App läuft ohne Sandbox, und die Hardened Runtime kennt kein Bluetooth-Entitlement.

### D7 Tests

- **GPSLoggerKit, `GNS2000DeviceTests` mit `GNS2000Simulator`** über ein eigenes `SimulatedDevice`:
  - NMEA-Rauschen;
  - Antwort auf `PGNS,R` mit Paketen, auf Wunsch mit gestörter Prüfsumme, Zeitsprung oder fehlendem Ende;
  - Antwort auf `PGNS,C` sofort oder erst nach Wiederholung.

  Abgedeckt sind alle Szenarien der Spec `gns2000-device` außer dem Katalog.
- **GPSLoaderKit:**
  - Katalogtest für den Eintrag.
  - `ProtocolDriver` mit einer Test-Fabrik, die einen Schein-Transport liefert: Mitschnitt über Bluetooth (Szenario „Mitschnitt über Bluetooth“).
  - Pufferlogik des RFCOMM-Transports mit simulierten Paketen (Szenario „Zeilen in mehreren Paketen“, „Gerät trennt die Verbindung“).
- **Nicht ohne Hardware testbar:** der echte IOBluetooth-Pfad (Öffnen, SDP, Berechtigung). Ihn prüfen Anwender (`docs/hardware-tests.md`).
- **iOS:** `xcodebuild -scheme GPSLoggerKit -destination 'generic/platform=iOS Simulator' build` muss gelingen.

## Risks / Trade-offs

- **Keine Hardware:** Fehler im Bluetooth-Pfad zeigen sich erst bei Anwendern. → Der Mitschnitt zeichnet auch Bluetooth auf; die Fehlermeldungen nennen Gerät und Dienst.
- **Berechtigungsdialog:** macOS fragt beim ersten Zugriff. Ohne Begründung im Info.plist würde die App beendet. → D6 und ein Test, dass der Schlüssel im gebauten Bundle steht.
- **API-Umzug:** Er berührt beide Pakete. → Er geschieht in einem eigenen ersten Task, mit vollem Testlauf vor dem neuen Treiber.
- **Byte 15:** Ungeprüfte Datensätze könnten beschädigt sein, wie in der Alt-App. → Der Anwendertest vergleicht mit myTracks bzw. der Hersteller-Software.

## Migration Plan

- Für Anwender: keine.
- Für Code außerhalb des Repositorys: Wer `DeviceProtocol` aus `GPSLoggerKitGPL` importiert hat, braucht `import GPSLoggerKit`. Betroffen sind nur App und GPSLoaderKit.
