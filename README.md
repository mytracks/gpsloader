# gpsloader

Eigenständige macOS-App zum Auslesen von GPS-Loggern und zum Konvertieren von Logger-Dateien nach GPX.
gpsloader löst die Logger-Funktionen von myTracks ab. Der Vertrieb läuft per Download, nicht über den App Store.

Planung und Anforderungen: `openspec/` (spec-getrieben mit OpenSpec), Hintergrund: `docs/legacy-analysis.md`.

## Voraussetzungen

- macOS mit **Xcode 27** (Swift 6.4, macOS-27-SDK); Deployment Target der App ist macOS 12.
- **XcodeGen** (`brew install xcodegen`). Das Xcode-Projekt wird aus `project.yml` erzeugt und nicht eingecheckt.
- Zum Signieren: Zertifikate „Apple Development“ und „Developer ID Application“ des Teams `4TNB35NY7G`.

## Bauen und starten

```sh
xcodegen generate
xcodebuild -project gpsloader.xcodeproj -scheme gpsloader -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/gpsloader.app
```

Alternativ nach `xcodegen generate` das Projekt `gpsloader.xcodeproj` in Xcode öffnen.

## Bedienung

Das Hauptfenster hat zwei Bereiche, umschaltbar in der Werkzeugleiste oder über „Darstellung“ (⌘1 „Dateien
konvertieren“, ⌘2 „Gerät auslesen“). Die App merkt sich den zuletzt gewählten Bereich; beim ersten Start ist
„Gerät auslesen“ gewählt.

- **Dateimodus:** „Ablage > Dateien konvertieren …“ (⌘O), „Dateien auswählen …“ bzw. ein Klick auf die Ablagefläche
  im Bereich „Dateien konvertieren“ oder Dateien per Drag & Drop auf das Hauptfenster (in beiden Bereichen; das
  Fenster schaltet dann auf „Dateien konvertieren“). Das Format wird am Inhalt erkannt. Mehrere Dateien ergeben eine GPX-Datei.
  - `GPSLoggerKit`: NMEA 0183, GPX, IGC, Garmin FIT, TCX, Suunto SML, KML/KMZ, Columbus V-900 und iBlue 747/757 (CSV).
  - `GPSLoggerKitGPL`: Speicherabbilder von SkyTraq-, MTK- und Holux-Loggern, Wintec TES/BIN/TK1, Locosys SBP/SBN
    und Medion-GoPal-Tracks.
- **Direktmodus:** Im Bereich „Gerät auslesen“ Gerät und Anschluss wählen, dann „Auslesen“ bzw. „Speicher löschen …“.
  Anschlüsse erscheinen mit sprechenden Namen („USB: … (Prolific PL2303)“, „Bluetooth: …“); ein Anschluss, dessen
  Name zum Gerät passt, steht oben und ist vorausgewählt, Systemanschlüsse sind ausgeblendet. Unter der Auswahl
  stehen Hinweise zum Gerät (z. B. M-241 nicht über Bluetooth, GNS 2000 vorher koppeln) und, wenn ein
  USB-Seriell-Chip ohne Anschluss steckt, ein Hinweis auf den fehlenden Treiber mit Link zum Hersteller.
  Native Treiber (`GPSLoggerKitGPL`) für SkyTraq, MTK/Holux, Wintec, Navilink und i-GotU (GT-800 seriell,
  übrige Modelle über USB-HID; Löschen experimentell).
- **Support:** „Hilfe > Support-Paket erstellen …“ oder der Knopf in der Fehlermeldung eines Vorgangs sichert ein ZIP
  mit System- und App-Informationen, App-Protokoll, Einstellungen, Anschlüssen und USB-Geräten, gekoppelten
  Bluetooth-Geräten (nur mit vorhandener Bluetooth-Berechtigung), den Diagnose-Mitschnitten der letzten
  10 Vorgänge und Absturzberichten. Jeder Teil lässt sich abwählen; Mitschnitte enthalten Positionsdaten.
  Der Mitschnitt läuft immer mit; das App-Protokoll liegt unter `~/Library/Logs/gpsloader/` (höchstens 5 MB).

## Tests

Die Geräte- und Protokolllogik liegt im lokalen Swift-Package `Packages/GPSLoaderKit` und ist ohne Hardware testbar:

```sh
swift test --package-path Packages/GPSLoggerKit
swift test --package-path Packages/GPSLoaderKit
```

`GPSLoggerKit` zusätzlich auf dem iOS-Simulator (im Paketordner):

```sh
xcodebuild test -scheme GPSLoggerKit -destination 'platform=iOS Simulator,OS=27.1,name=<iPhone>'
```

Lokalisierung prüfen (nach einem Debug-Build, siehe oben):

```sh
swift Scripts/check-localizations.swift
```

### Debug-Hilfen

Debug-Builds enthalten einen Demo-Treiber und Startargumente, um UI-Zustände ohne Hardware zu prüfen
(siehe `App/DebugAutomation.swift`), zum Beispiel:

```sh
build/DerivedData/Build/Products/Debug/gpsloader.app/Contents/MacOS/gpsloader \
    -DebugDemo success -AppleLanguages '(de)'
```

Dateikonvertierung ohne Dialoge (schreibt nach `-DebugSaveDirectory`, Bildschirmfotos nach `-DebugSnapshotDirectory`):

```sh
build/DerivedData/Build/Products/Debug/gpsloader.app/Contents/MacOS/gpsloader \
    -DebugConvert /pfad/a.nmea,/pfad/b.igc -DebugSaveDirectory /tmp/out -DebugQuitAfter 5
```

Bereich vorgeben (`-DebugSection files|device`), Tastenkürzel über das Menü senden (`-DebugKeyEquivalent 2`) und
Zeitpunkte der Bildschirmfotos wählen (`-DebugSnapshotTimes 1.5,3`).

Support-Paket ohne Dialoge schreiben (`-DebugShowSupportPackage <s>` öffnet stattdessen den Dialog,
`-DebugNoBluetoothPermission YES` zeigt ihn wie ohne Bluetooth-Berechtigung):

```sh
build/DerivedData/Build/Products/Debug/gpsloader.app/Contents/MacOS/gpsloader \
    -DebugSupportPackagePath /tmp/support.zip -DebugQuitAfter 4
```

Anschlussnamen und Hinweise ohne Hardware prüfen (erfundene Anschlüsse und USB-Geräte, siehe `DebugPorts` in
`App/DevicePanel.swift`):

```sh
build/DerivedData/Build/Products/Debug/gpsloader.app/Contents/MacOS/gpsloader \
    -DebugPorts "bt:/dev/cu.HOLUX_M-241-SPPSlave,usb:/dev/cu.usbserial-1410:067B:2303:USB-Serial Controller" \
    -DebugUSBDevices "067B:2303" -DebugSelectDevice m241.holux-m-241 -DebugSnapshotDirectory /tmp/snap -DebugQuitAfter 3
```

Gerät aus dem Katalog auslesen, z. B. gegen ein simuliertes Gerät an einem Pseudo-Terminal:

```sh
build/DerivedData/Build/Products/Debug/gpsloader.app/Contents/MacOS/gpsloader \
    -DebugReadDevice skytraq.venus -DebugPort /dev/ttys012 -DebugSaveDirectory /tmp/out -DebugQuitAfter 10
```

## Release

```sh
Scripts/release.sh                      # Archiv, Developer-ID-Export, Notarisierung, Stapling -> build/release/gpsloader-<Version>.zip
Scripts/release.sh --skip-notarize      # nur signiertes ZIP für eigene Tests, nicht für Anwender
Scripts/release.sh --allow-unpublished  # notarisieren, ohne zu prüfen, dass der Commit sauber und gepusht ist
Scripts/verify-bundle.sh <App>          # Signaturen, Hardened Runtime, Architekturen, Lizenzen prüfen
```

Vor dem langen Build prüft `release.sh`, dass der Commit sauber und auf `origin` gepusht ist (GPL: Quelle jeder Version
öffentlich), dass das Notarisierungsprofil funktioniert und dass das Developer-ID-Zertifikat da ist. Das ZIP für die
Anwender enthält die App mit angeheftetem Notarisierungs-Ticket (Stapling); daneben liegt `gpsloader-<Version>.zip.sha256`. Lehnt Apple ab, liegt das Protokoll in
`build/release/notarization-log.json`.

Einmalig das Keychain-Profil für die Notarisierung anlegen:

```sh
xcrun notarytool store-credentials gpsloader-notary --apple-id <Apple-ID> --team-id 4TNB35NY7G
```

## Aufbau

| Ort | Inhalt |
|---|---|
| `App/` | AppKit-App (UI, Lokalisierung `Localizable.xcstrings`) |
| `Packages/GPSLoggerKit/` | Eigenständiges Paket (MIT, macOS 12+ und iOS 27+): Datenmodell, Dateiformate (NMEA, GPX, IGC, FIT, TCX, Suunto SML, KML/KMZ, V-900, iBlue-CSV), Geräteschnittstelle und GNS-2000-Treiber, GPX-Ausgabe. Wird später in ein eigenes Repository ausgelagert; siehe dessen `README.md` und `PROVENANCE.md` |
| `Packages/GPSLoggerKitGPL/` | Paket für Formate und Treiber, die aus GPL-Quellen portiert sind (GPL-3.0-or-later, nur macOS). Ergänzt den Katalog von GPSLoggerKit; Regeln für Portierungen in `Packages/GPSLoggerKitGPL/README.md` |
| `Packages/GPSLoaderKit/` | `LoggerCore` (Treibervertrag, Session), `SerialTransport`, `GPXExport` (Dateiname, Schreiben), `DiagnosticCapture`, `FileConversion` (Dateimodus: Erkennen, Zusammenführen), `DeviceDrivers` (Gerätekatalog, Anbindung der Treiber), `HIDTransport` (USB-HID), `BluetoothTransport` (Bluetooth-RFCOMM, GNS 2000), `SupportPackage` (App-Protokoll, Support-Paket), `TestSupport` |
| `Vendor/Licenses/` | Lizenztexte für das App-Bundle: GPL-3.0 (Kopie von `LICENSE`) und die MIT-Lizenz von GPSLoggerKit |
| `Scripts/` | Release, Bundle-Prüfung, Lokalisierungsprüfung |

## Ohne gpsbabel

gpsloader liest alle Formate und Geräte mit eigenen Swift-Treibern (GPSLoggerKit und GPSLoggerKitGPL). Bis
2026-11-13 lag gpsbabel 1.7.0 samt Qt bei; seit dem Change `remove-gpsbabel` enthält die App keine
Hilfsprogramme mehr und braucht auch auf Apple Silicon kein Rosetta. Für Black-Box-Gegenprüfungen von
Portierungen wird das gpsbabel-1.7.0-Binary aus der myTracks-Historie (Commit `e0d1f18`) in einen
temporären Ordner kopiert, nie ins Repository.

Nicht mehr unterstützt werden die 45 Formate von Karten- und Navigationsprogrammen, die myTracks über gpsbabel
anbot (z. B. OziExplorer, Garmin MapSource, CompeGPS); die Liste steht im Proposal von `remove-gpsbabel`.

## Lizenz

- gpsloader (App, `GPSLoaderKit`) und `GPSLoggerKitGPL` stehen unter der **GNU GPL Version 3
  oder später** (GPL-3.0-or-later, siehe `LICENSE`). Wer die App weitergibt, muss den vollständigen Quellcode
  anbieten.
- `GPSLoggerKit` steht unter der **MIT-Lizenz** (`Packages/GPSLoggerKit/LICENSE`) und enthält keinen aus
  GPL-Quellen abgeleiteten Code.
