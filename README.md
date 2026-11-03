# gpsloader

Eigenständige macOS-App zum Auslesen von GPS-Loggern und zum Konvertieren von Logger-Dateien nach GPX.
gpsloader löst die Logger-Funktionen von myTracks ab. Der Vertrieb läuft per Download, nicht über den App Store.

Planung und Anforderungen: `openspec/` (spec-getrieben mit OpenSpec), Hintergrund: `docs/legacy-analysis.md`.

## Voraussetzungen

- macOS mit **Xcode 27** (Swift 6.4, macOS-27-SDK); Deployment Target der App ist macOS 12.
- **XcodeGen** (`brew install xcodegen`). Das Xcode-Projekt wird aus `project.yml` erzeugt und nicht eingecheckt.
- Für Tests, die das gebündelte gpsbabel wirklich ausführen, auf Apple Silicon **Rosetta 2**:
  `softwareupdate --install-rosetta --agree-to-license`.
  Ohne Rosetta laufen alle automatischen Tests trotzdem; die App zeigt dann „Rosetta fehlt“.
- Zum Signieren: Zertifikate „Apple Development“ und „Developer ID Application“ des Teams `4TNB35NY7G`.

## Bauen und starten

```sh
xcodegen generate
xcodebuild -project gpsloader.xcodeproj -scheme gpsloader -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/gpsloader.app
```

Alternativ nach `xcodegen generate` das Projekt `gpsloader.xcodeproj` in Xcode öffnen.

## Tests

Die Geräte- und Protokolllogik liegt im lokalen Swift-Package `Packages/GPSLoaderKit` und ist ohne Hardware testbar:

```sh
swift test --package-path Packages/GPSLoaderKit
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
    -DebugDemo success -DebugSimulatedStatus ready -AppleLanguages '(de)'
```

## Release

```sh
Scripts/release.sh                  # Archiv, Developer-ID-Export, Notarisierung, Stapling -> build/release/gpsloader-<Version>.zip
Scripts/release.sh --skip-notarize  # nur signiertes ZIP
Scripts/verify-bundle.sh <App>      # Signaturen, Hardened Runtime, Architekturen, Lizenzen prüfen
```

Einmalig das Keychain-Profil für die Notarisierung anlegen:

```sh
xcrun notarytool store-credentials gpsloader-notary --apple-id <Apple-ID> --team-id 4TNB35NY7G
```

## Aufbau

| Ort | Inhalt |
|---|---|
| `App/` | AppKit-App (UI, Lokalisierung `Localizable.xcstrings`) |
| `RosettaInstaller/` | Hilfs-App nur für x86_64; ihr Start löst den Rosetta-Installationsdialog von macOS aus |
| `Packages/GPSLoaderKit/` | `LoggerCore` (Modell, Treibervertrag, Session), `SerialTransport`, `GPSBabelRuntime`, `GPXExport`, `DiagnosticCapture`, `TestSupport` |
| `Vendor/gpsbabel-1.7.0/` | gpsbabel 1.7.0 (x86_64) und Qt Core 5.12.9 aus myTracks, Lizenztexte, Herkunftsnachweis |
| `Scripts/` | Signieren der Helfer (Build-Phase), Release, Bundle-Prüfung, Lokalisierungsprüfung |

## gpsbabel

gpsloader liefert **gpsbabel 1.7.0** als eigenständiges Programm mit (`Contents/Helpers/gpsbabel`), weil neuere
Versionen viele Logger-Formate (u. a. `wbt`, `navilink`, `magellan`) nicht mehr kennen. Das Binary ist nur für
x86_64 verfügbar und braucht auf Apple Silicon Rosetta 2. Herkunft und Prüfsummen: `Vendor/gpsbabel-1.7.0/PROVENANCE.md`.

Lizenzen: gpsbabel steht unter der GNU GPL v2 (oder später), Qt unter der GNU LGPL v3. Die Lizenztexte liegen im
App-Bundle unter `Contents/Resources/Licenses`. Der Quellcode beider Projekte muss zusammen mit dem Download
angeboten werden.
