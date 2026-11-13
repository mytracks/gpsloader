# Proposal: Direktmodus – Gerät wählen und auslesen

## Why

Der Direktmodus ist der Kern von gpsloader: Gerät wählen, Daten auslesen, GPX speichern und optional den Speicher löschen (`openspec/config.yaml`, Produkt). Das Hauptfenster zeigt bisher nur „Gerätetreiber folgen in kommenden Versionen“. Sitzungsablauf, Fortschritt, Abbruch, Zeitlimit, Speichern, Löschbestätigung (`logger-session`) und der serielle Transport (`serial-transport`) gibt es schon, nur die Gerätewahl und die Treiber fehlen. Am 2026-11-13 hat der Entwickler beauftragt, das Auslesen für SkyTraq, MTK, Wintec, Navilink und i-GotU umzusetzen. Dieser Change schafft das gemeinsame Gerüst, die Treiber folgen je Familie in eigenen Changes.

## What Changes

- **Geräteprotokolle im GPL-Paket:** GPSLoggerKitGPL bekommt eine eigene, kleine Verbindungs-Schnittstelle `DeviceConnection` und den Treibervertrag `DeviceProtocol`.
  - **Abhängigkeiten:** Das Paket hängt weiter nur von GPSLoggerKit ab.
  - **Inhalt der Verbindung:** schreiben, Bytes oder bis zu einem Endezeichen lesen, Eingang verwerfen, Baudrate wechseln.
  - **Inhalt des Vertrags:** auslesen, löschen, Fortschritt melden.
- **Anbindung in GPSLoaderKit:** Das neue Modul `DeviceDrivers` enthält einen Adapter, der jeden Treiber des GPL-Pakets als `LoggerDriver` an `LoggerSession` anschließt.
  - Er nutzt `SerialPort`.
  - Er schreibt den Diagnose-Mitschnitt über `CapturingTransport`.
  - Er bildet Protokollfehler auf `LoggerError` ab.
- **Gerätekatalog:** Er führt die Geräte der Familien SkyTraq, MTK, Holux, Wintec, Navilink und i-GotU aus `docs/legacy-device-catalog.md`, jeweils mit Treiber, Baudraten, Verbindungsart und Löschunterstützung. Einträge kommen mit dem Treiber ihrer Familie dazu.
- **`SerialPort`:** Die Baudrate lässt sich bei offenem Port wechseln. SkyTraq braucht das.
- **Hauptfenster, Bereich „Gerät“:**
  - Auswahl von Gerät und Anschluss, live aktualisiert über `SerialPortCatalog.changes()`.
  - Die Knöpfe „Auslesen“ und „Speicher löschen …“; letzterer nur, wenn der Treiber löschen kann.
  - Die Auswahl wird gemerkt.
  - Geräte ohne seriellen Anschluss (i-GotU über USB-HID) brauchen keine Portwahl.

## Capabilities

### New Capabilities

- `device-mode`: Gerätewahl, Anschlusswahl und Start von Auslesen und Löschen im Hauptfenster, Gerätekatalog und Anbindung der Treiber.

### Modified Capabilities

- `serial-transport`: Baudrate bei offenem Port wechseln.
- `logger-kit-gpl`: Verbindungs-Schnittstelle und Treibervertrag für Geräteprotokolle.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- Dieser Change bringt noch keine Treiber mit. Der Katalog ist vorbereitet für die Treiber `skytraq`, `mtk`, `m241`, `wbt` und `navilink` sowie für i-GotU (Analyse, Abschnitt 3.2).
- Die übrigen Geräte des Katalogs (gpsbabel-Treiber wie `magellan`, interne Treiber BG728/GNS2000) sind nicht Teil der Aufträge vom 2026-11-13.

## Nicht im Umfang

- **Einrichtungsassistent der Alt-App** (Abstecken und Anstecken, Analyse Abschnitt 6): Die Portliste zeigt USB-Namen und aktualisiert sich live, das genügt.
- **Treiber über gpsbabel im Direktmodus:** Die Familien dieses Auftrags laufen nativ.
- **BG728, GNS2000 und Magellan:** eigene Changes.

## Impact

- **GPSLoggerKitGPL:** neue Dateien `Device/DeviceConnection.swift` und Test-Helfer für simulierte Geräte.
- **GPSLoaderKit:** neues Modul `DeviceDrivers`, `SerialPort.setBaudRate(_:)`.
- **App:** Der Bereich „Gerät“ im `MainWindowController` wird ersetzt. Dazu kommen Lokalisierung, `project.yml` (neues Paketprodukt) und Tests.
