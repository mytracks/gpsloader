# Proposal: device-ports-and-hints

## Why

Die Anschlusswahl zeigt heute Namen wie `usbserial-1410 (/dev/cu.usbserial-1410)`, auch Systemanschlüsse wie
`Bluetooth-Incoming-Port` und `debug-console`. Anwender erkennen darin ihren Logger nicht. Hinweise gibt es nur
für „kein Anschluss vorhanden“. Der Entwickler hat am 2026-11-14 festgestellt, dass der Holux M-241 unter
macOS 27 über Bluetooth zwar einen Anschluss `/dev/cu.*` bekommt, das Auslesen darüber aber scheitert; über USB
geht es. Solche Erfahrungen und fehlende USB-Seriell-Treiber soll die App dem Anwender direkt nennen, bevor
gpsloader an Anwender geht (Exploration vom 2026-11-14).

## What Changes

- **Art des Anschlusses:** `SerialTransport` erkennt, ob ein Anschluss zu einem USB-Gerät, zu einem gekoppelten
  Bluetooth-Gerät oder zum System gehört, und listet die angeschlossenen USB-Geräte.
- **Sprechende Namen:** Die Anschlusswahl zeigt z. B. „USB-Seriell (Silicon Labs CP210x)“ oder
  „Bluetooth: HOLUX_M-241“. Anschlüsse, deren Name zum gewählten Gerät passt, stehen oben und sind vorausgewählt,
  danach USB, dann Bluetooth. Systemanschlüsse sind ausgeblendet. Der Pfad erscheint als Tooltip.
- **Hinweise pro Gerät** im Gerätebereich:
  - Holux M-241 mit gewähltem Bluetooth-Anschluss: „über USB verbinden“, auch in der Fehlermeldung einer
    Zeitüberschreitung.
  - GNS 2000: vorher in den Systemeinstellungen koppeln.
  - i-GotU: direkt per USB anschließen, keine Anschlusswahl.
  - Alle seriellen Geräte: Steckt ein USB-Gerät mit dem Chip eines bekannten USB-Seriell-Herstellers (Silicon
    Labs, Prolific, FTDI, WCH), ohne dass ein Anschluss dazu existiert, fehlt vermutlich der Treiber; der Hinweis
    nennt den Hersteller und verlinkt dessen Treiberseite.

Betroffen sind die Geräte aller seriellen Familien aus `docs/legacy-device-catalog.md` (SkyTraq, MTK/Holux,
Wintec, Navilink, Magellan, iTrackU) sowie GNS 2000 und i-GotU durch ihre Hinweise. Neue Familien entstehen nicht.

## Capabilities

### New Capabilities

(keine)

### Modified Capabilities

- `serial-transport`: Art des Anschlusses und Liste der USB-Geräte.
- `device-mode`: Anschlusswahl mit sprechenden Namen, Sortierung und ohne Systemanschlüsse; Hinweise pro Gerät.

## Nicht im Umfang

- Treiber installieren oder Systemeinstellungen öffnen; die App verlinkt nur.
- Geräte anhand von USB-Hersteller- und Produkt-ID erkennen; die IDs der Logger sind nicht bekannt.
  Hinweise auf weitere Geräte kommen, wenn Anwender sie melden.
- Gekoppelte Bluetooth-Geräte ohne Anschluss erkennen (bräuchte die Bluetooth-Berechtigung).
- Die Fensteraufteilung (Change `main-window-sections`).

## Impact

- `SerialTransport`: `SerialPortInfo.kind`, `USBDeviceCatalog` (aus Change `support-package`) wird für die
  Treibererkennung genutzt.
- `DeviceDrivers`: `DeviceEntry.hints`, `PortPresentation` (Sortierung, Erkennung des passenden Anschlusses),
  `DeviceSelection` mit den neuen Hinweisen.
- App: `DevicePanel` (Namen, Tooltip, Hinweisbereich mit Links), `SessionPresenter` (Hinweis in der
  Fehlermeldung), Lokalisierung.
