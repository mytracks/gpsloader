# Design: device-ports-and-hints

## Context

- `SerialPortCatalog` (SerialTransport) listet `/dev/cu.*` über `IOSerialBSDClient` und liest USB-Angaben aus den
  Eltern im IORegistry (`idVendor`, `idProduct`, `USB Product Name`, `USB Vendor Name`).
- Bluetooth-Anschlüsse hängen unter einem `IOBluetoothDevice` mit den Eigenschaften `BTAddress` und `BTTTYName`
  (beobachtet auf macOS 27 mit `ioreg -r -c IOSerialBSDClient`: `cu.Bluetooth-Incoming-Port` und ein
  gekoppelter GNS 2000 als `cu.GNS2000`). `debug-console` hängt an einem internen UART ohne USB/Bluetooth.
- `DevicePanel` (App) baut die Titel selbst; `DeviceSelection` (DeviceDrivers) kennt nur den Hinweis `noPort`
  und bevorzugt beim Vorauswählen den ersten USB-Anschluss.
- Der Change `support-package` führt `USBDeviceCatalog.currentDevices()` in SerialTransport ein.
- Alt-App: `GpsLoggerWizard.m` bevorzugt `SLAB_USBtoUART` und lässt bei Bluetooth aus der `cu.*`-Liste wählen
  (`input/mytracks4mac/myTracks/Source/Classes/Controller/GpsLoggerWizard.m`, siehe `docs/legacy-analysis.md`).

## Goals / Non-Goals

**Goals:**
- Namen, Sortierung und Hinweise ohne AppKit testbar (DeviceDrivers), die App setzt nur Texte ein.
- Hinweise als Daten im Katalog, damit neue Erfahrungen von Anwendern nur einen Eintrag brauchen.

**Non-Goals:**
- Keine Erkennung von Loggern an USB-IDs, keine Bluetooth-Abfragen über IOBluetooth.

## Decisions

### D1 Art des Anschlusses in `SerialPortInfo`

Neues Feld `kind: SerialPortKind` (`.usb`, `.bluetooth`, `.system`, `.other`) und `usbLocationID: Int?`.
`.bluetooth`, wenn bei den Eltern `BTAddress` existiert; `.usb`, wenn `idVendor` existiert; `.system` für
`Bluetooth-Incoming-Port` und für Anschlüsse ohne USB/Bluetooth, deren Name `debug` enthält (z. B.
`debug-console`, `wlan-debug`). Die Einordnung ist eine statische Funktion über die gelesenen Eigenschaften,
damit Tests sie ohne IORegistry prüfen. Alternative: Klassennamen der Eltern prüfen – verworfen, die Klassen
heißen je macOS-Version anders (`IOUserBluetoothSerialDriver` seit DriverKit).

### D2 Bekannte USB-Seriell-Chips

`USBSerialChip` (DeviceDrivers) ordnet Hersteller-IDs zu: Silicon Labs 0x10C4 (CP210x), Prolific 0x067B (PL2303),
FTDI 0x0403, WCH 0x1A86 (CH34x). Jede Zuordnung hat einen Anzeigenamen und eine Treiberseite:

| Hersteller | Treiberseite |
|---|---|
| Silicon Labs | https://www.silabs.com/software-and-tools/usb-to-uart-bridge-vcp-drivers |
| Prolific | Mac App Store „PL2303 Serial“: https://apps.apple.com/app/pl2303-serial/id1624835354 |
| FTDI | https://ftdichip.com/drivers/vcp-drivers/ |
| WCH | https://github.com/WCHSoftGroup/ch34xser_macos |

Geprüft am 2026-11-14: Prolific-App (Prolific Technology Inc., ab macOS 11) und WCH-Repository erreichbar;
Silicon Labs und FTDI sind laut Websuche die offiziellen Seiten, lehnen automatische Abrufe aber ab (HTTP 403) –
vor dem Release im Browser prüfen (Task 4.2).

### D3 Darstellung und Reihenfolge der Anschlüsse

`PortPresentation.list(ports:for:)` liefert die sichtbaren Anschlüsse in Reihenfolge, je mit
`label: PortLabel` (`.usb(product: String?, chip: String?)`, `.bluetooth(name:)`, `.other(name:)`) und
`matchesDevice: Bool`. Systemanschlüsse fallen weg. Passend ist ein Anschluss, wenn sein Name, reduziert auf
Buchstaben und Ziffern in Kleinschrift, den ebenso reduzierten Gerätenamen oder den Gerätenamen ohne erstes Wort
(mindestens 4 Zeichen) enthält: „Holux M-241“ → `holuxm241`/`m241` passt zu `HOLUX_M-241-SPPSlave`.
Reihenfolge: passend, USB, Bluetooth, übrige; innerhalb nach Pfad. `DeviceSelection.port(preferring:)` nimmt
den gespeicherten Anschluss, sonst den ersten dieser Liste. Die App formatiert die Titel lokalisiert und setzt
den Pfad als Tooltip.

### D4 Hinweise im Katalog

```swift
public struct DeviceHint: Sendable, Equatable {
    public enum Condition: Sendable { case always, bluetoothPort }
    public enum Message: Sendable, Equatable { case useUSBInsteadOfBluetooth, pairInSystemSettings, connectDirectlyViaUSB }
    public var condition: Condition
    public var message: Message
}
```

`DeviceEntry.hints: [DeviceHint]` (Standard leer). Einträge: Holux M-241 `(.bluetoothPort, .useUSBInsteadOfBluetooth)`,
GNS 2000 `(.always, .pairInSystemSettings)`, i-GotU `(.always, .connectDirectlyViaUSB)`.
`DeviceSelection.hints(entries:ports:usbDevices:)` liefert `[DeviceSelection.Hint]` mit `.noPort`,
`.device(DeviceHint.Message)` und `.driverMissing(USBSerialChip)`. Die Texte stehen in der App (de/en), damit
DeviceDrivers ohne Ressourcen bleibt.

### D5 Fehlender Treiber

`driverMissing`, wenn das Gerät seriell ist und ein USB-Gerät einer Chip-Hersteller-ID steckt, zu dem kein
Anschluss gehört (gleiche `locationID`, ersatzweise gleiche Hersteller- und Produkt-ID). Die USB-Liste wird bei
jeder Änderung der Anschlüsse neu gelesen; zusätzlich beobachtet die App das Anstecken von USB-Geräten über
`USBDeviceCatalog.changes()` (IOKit-Benachrichtigung wie bei den Anschlüssen), weil ohne Treiber kein Anschluss
erscheint.

### D6 Hinweis in der Fehlermeldung

`DevicePanel` gibt beim Start eines Lesevorgangs die zutreffenden Hinweise mit `Condition.bluetoothPort` an
`SessionPresenter`; endet der Vorgang mit einem Fehler (`SessionOutcome.failed`), stellt `showError` sie vor den
Text. Ursprünglich nur für Zeitüberschreitungen geplant; beim Test mit einem stummen Anschluss meldet der
MTK-Treiber aber „kein MTK-Logger“ (Protokollfehler), sodass der Hinweis gerade im Fall des M-241 gefehlt hätte
(geändert bei der Umsetzung am 2026-11-14).

## Risks / Trade-offs

- [Namensvergleich trifft falsche Anschlüsse] → nur Sortierung und Vorauswahl, der Anwender kann umwählen.
- [Apple-Treiber für CP210x/PL2303/FTDI/CH34x machen den Hinweis selten] → er erscheint nur, wenn tatsächlich kein Anschluss entsteht.
- [Hinweis-Texte zu Geräten beruhen auf einzelnen Beobachtungen] → Bedingung und Text so formuliert, dass sie nicht falsch sind („lässt sich nicht zuverlässig auslesen“).
