# Proposal: GNS 2000 über Bluetooth auslesen und löschen

## Why

Der Bluetooth-Logger GNS 2000 (auch „GNS 2000 plus“) lief in myTracks über einen internen Treiber. Der wurde nicht über gpsbabel angesprochen, sondern direkt über IOBluetooth. In gpsloader fehlt er bisher; er ist einer der drei noch offenen nativen Treiber neben BG728 und WSG-2000 NAL. Der Entwickler hat am 2026-11-13 die Unterstützung beauftragt.

## What Changes

- **Treiber in GPSLoggerKit:** `GNS2000Device` (MIT), Clean-Room nach dem eigenen myTracks-Code des Entwicklers (`GNS2000.m`, siehe `docs/legacy-analysis.md`, Abschnitt `*GNS2000`).
  - Auf den ersten NMEA-Satz warten.
  - Lesen mit `$PGNS,R` und der Antwortfolge `$PMTKLOX,0/1/2`, dabei 16-Byte-Datensätze dekodieren.
  - Ein neuer Track beginnt, wenn die Zeit zurückspringt.
  - Löschen mit `$PGNS,C`, bestätigt durch `$PMTK001`.
  - Neu gegenüber der Alt-App: Zeitlimits, Fortschritt und Abbruch. Die Alt-App konnte ohne Zeitlimit hängen bleiben.
- **Geräteschnittstelle nach GPSLoggerKit:** `DeviceConnection`, `DeviceProtocol`, `DeviceReporter`, `DeviceProtocolError` und `DeviceErase` ziehen von GPSLoggerKitGPL nach GPSLoggerKit.
  - Es ist eigener Code aus `device-mode`, kein Teil einer Portierung.
  - Das GPL-Paket nutzt die Schnittstelle von dort; die Namen bleiben gleich.
  - Damit können Treiber aus eigenem Code (GNS2000, später BG728) unter MIT entstehen.
  - Die Schnittstelle ist plattformneutral, der iOS-Build bleibt möglich.
- **Neues Modul `BluetoothTransport` in GPSLoaderKit:** ein RFCOMM-Kanal über IOBluetooth als `ByteTransport`.
  - Es sucht das gekoppelte Gerät nach Namen und den SDP-Dienst „GNS GPS“.
  - Der Diagnose-Mitschnitt läuft wie bei seriellen Geräten über `CapturingTransport`.
- **Gerätekatalog:** neue Verbindungsart „Bluetooth (RFCOMM)“, ohne Anschlusswahl. Dazu ein Eintrag „GNS 2000“ für beide Modellnamen, mit Löschen.
- **App:**
  - `NSBluetoothAlwaysUsageDescription` (de/en), weil macOS den Zugriff auf Bluetooth erst nach Zustimmung erlaubt.
  - Der Bluetooth-Transport wird an das Gerätepanel übergeben, wie der HID-Transport.
- **Dokumentation:** `openspec/config.yaml` (Zuordnung, Treiber-Architektur), `PROVENANCE.md` und `README.md` von GPSLoggerKit und `docs/hardware-tests.md`.

## Zuordnung der Familie

- **GNS 2000:** GPSLoggerKit, Clean-Room. Entscheidung des Entwicklers vom 2026-11-13.
- **Grundlage:**
  - der eigene myTracks-Code des Entwicklers (`input/mytracks4mac/DsTrackFramework/Source/Classes/GpsDriver/GNS2000.m` und `GNS2000.h`, © 2013 Dirk Stichling);
  - die Analyse in `docs/legacy-analysis.md`.
- **Kein GPL-Quelltext:** gpsbabels `mtk_locus.cc` und ähnliche Quellen werden nicht gelesen.
- **Geräteschnittstelle:** Sie ist ebenfalls eigener Code (Change `device-mode`, Dateikopf „Own code“). Der Umzug nach GPSLoggerKit verstößt nicht gegen die Regel, dass portierte Familien im GPL-Paket bleiben: Die Schnittstelle selbst ist keine Portierung.

## Capabilities

### New Capabilities

- `gns2000-device`: Track des GNS 2000 über Bluetooth lesen und den Speicher löschen, mit Gerätekatalog-Eintrag.
- `bluetooth-transport`: Verbindung zu einem gekoppelten Bluetooth-Gerät über einen RFCOMM-Kanal eines SDP-Dienstes.

### Modified Capabilities

- `logger-kit`: GPSLoggerKit stellt die Geräteschnittstelle (Verbindung und Treibervertrag) bereit.
- `logger-kit-gpl`: Die Geräteprotokolle des GPL-Pakets nutzen die Schnittstelle aus GPSLoggerKit, statt eine eigene bereitzustellen.
- `device-mode`: Der Katalog kennt die Verbindungsart Bluetooth. Der Adapter betreibt Treiber aus beiden Paketen.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Bluetooth (seriell/RFCOMM), Treiber `*GNS2000`:** GNS 2000. Die Alt-App erkannte am Namen auch „GNS 2000 plus“.

## Nicht im Umfang

- **Abfrage der Geräteversion** (`$PGNS,V,3`): Die Alt-App nutzte sie nicht.
- **Zeitzone im Track-Namen:** Die Alt-App benannte Tracks nach der Ortszeit aus ihren Einstellungen. gpsloader hat keine solche Einstellung; die GPX-Zeiten bleiben UTC.
- **Koppeln aus der App heraus:** Das Gerät muss in den Systemeinstellungen gekoppelt sein.
- **Andere Bluetooth-Logger:** Sie laufen weiter über `/dev/cu.*`.
- **Tests mit Hardware durch den Entwickler:** Er hat keinen GNS 2000; den Test übernehmen Anwender.
- **iOS:** Die Treiberlogik baut dort, einen Bluetooth-Transport gibt es aber nur unter macOS.

## Impact

- **GPSLoggerKit:**
  - neu `Sources/GPSLoggerKit/Device/` (Schnittstelle, aus dem GPL-Paket verschoben) und `Sources/GPSLoggerKit/Devices/GNS2000/`;
  - Tests mit simuliertem Gerät;
  - `PROVENANCE.md`, `README.md`.
- **GPSLoggerKitGPL:** `Device/DeviceProtocol.swift` entfällt. Treiber und Tests nutzen die Typen aus GPSLoggerKit; das Test-Hilfsmittel `SimulatedDevice` bleibt.
- **GPSLoaderKit:**
  - neues Modul `BluetoothTransport`;
  - in `DeviceDrivers`: `DeviceConnectionKind.bluetooth`, `BluetoothTransportFactory`, `ProtocolDriver`, `Families/GNS2000Devices.swift`.
- **App:** `DevicePanel`/`MainWindowController` (Transport-Fabrik), `Info.plist`-Schlüssel samt Übersetzung, `project.yml` (Produkt `BluetoothTransport`).
- **Dokumentation:** `openspec/config.yaml`, `docs/hardware-tests.md`.
