# Tasks: gpl-driver-package

## 1. Zusammensetzbarer Katalog in GPSLoggerKit

- [x] 1.1 `FormatCatalog` nach design.md D2 anlegen (`init`, `all`, `format(withID:)`, `detect(prefix:fileName:)`, `standard`, `adding(_:)`, interne Hilfe `duplicateIDs(in:)` für die `precondition`). `FileFormats.detect` und `FileFormats.format(withID:)` delegieren auf `.standard`. Prüfen: Die bestehenden Tests sind unverändert grün.
- [x] 1.2 Tests zu 1.1 mit einem Testformat (D7). Prüfen:
  - Das Szenario „Zusätzliches Format erkennen“ der Spec `logger-kit` ist abgedeckt, ebenso „Standardkatalog unverändert“.
  - Die eigenen Formate stehen vorn, `duplicateIDs` findet eine doppelte Kennung.
  - Die README von GPSLoggerKit zeigt die Verwendung in einem Beispiel und nennt kein bestimmtes Fremdpaket.

## 2. Paket GPSLoggerKitGPL

- [x] 2.1 `Packages/GPSLoggerKitGPL` nach D1 anlegen: `Package.swift` (macOS 12, Swift 6, Abhängigkeit nur auf `../GPSLoggerKit`), `LICENSE` (GPL-3.0-Text, identisch mit `Vendor/gpsbabel-1.7.0/Licenses/GPL-3.0.txt`), `GPLFileFormats` mit leerem `all` und leerem `credits`, Typ `Credit`, `PROVENANCE.md` mit Einleitung und ohne Formatabschnitte, `README.md` mit Lizenz, Zweck und den Regeln aus D6. Prüfen: `swift build` im Paket gelingt ohne Warnungen.
- [x] 2.2 Tests zu 2.1 (D7). Prüfen:
  - Die Szenarien „Lizenzdatei“, „Leerer Katalog“ und „Eindeutige Kennungen“ der Spec `logger-kit-gpl` sind abgedeckt.
  - Der Provenance-Test erkennt einen fehlenden Abschnitt.
  - Der Test zu `credits` ist vorhanden.
- [x] 2.3 Die Ordner `GPSLoggerKitGPL` und `GPSLoggerKit` gemeinsam in den Scratchpad kopieren und dort `swift test` ausführen, dazu GPSLoggerKit allein. Prüfen: Die Szenarien „Bauen mit GPSLoggerKit allein“ und „Keine Rückabhängigkeit“ sind erfüllt, `grep` findet in Code, Tests und `Package.swift` von GPSLoggerKit keinen Verweis auf `GPSLoggerKitGPL`. Die README darf nach 5.2 darauf verweisen.

## 3. Katalog der App

- [x] 3.1 `FileConversion` hängt nach D3 von GPSLoggerKitGPL ab. Dazu `AppFormats` (`catalog`, `credits`) und der Parameter `catalog` für `FileConverter.plan` und `convert`. Prüfen: Die Tests von GPSLoaderKit sind grün.
- [x] 3.2 Test zu 3.1: Ein Katalog mit Testformat konvertiert eine Testdatei zusammen mit einer NMEA-Datei. Prüfen: Das Szenario „Format aus dem GPL-Paket“ der Spec `file-conversion` ist abgedeckt.
- [x] 3.3 `ConversionPresenter` listet `AppFormats.catalog.all`. Prüfen: Der Bereich „Dateien“ im Hauptfenster zeigt unverändert alle sieben Formate (Snapshot).

## 4. Lizenzen und Über-Fenster

- [x] 4.1 `LICENSE` (GPL-3.0) ins Wurzelverzeichnis, dazu der Abschnitt „Lizenz“ in `README.md` nach D4. `Vendor/Licenses/MIT-GPSLoggerKit.txt` als Kopie von `Packages/GPSLoggerKit/LICENSE` anlegen, in `project.yml` nach `Contents/Resources/Licenses` kopieren und in `Scripts/verify-bundle.sh` prüfen. Ein Test in GPSLoaderKit vergleicht Kopie und Original. Prüfen: `xcodegen` und Build gelingen, `verify-bundle.sh` ist für den Debug-Build grün.
- [x] 4.2 Quellcode-Adresse nach D5: Build-Einstellung `GPSLOADER_SOURCE_CODE_URL` (leer), Teil-Plist `App/Info.plist`, Release-Prüfung in `verify-bundle.sh`. Prüfen: Das gebaute Bundle enthält den Schlüssel, und `verify-bundle.sh` meldet für einen Release-Build ohne Adresse einen Fehler.
- [x] 4.3 Über-Fenster nach D5: Lizenz der App mit Link (nur bei gesetzter Adresse), GPSLoggerKit (MIT) mit Lizenzbutton, Abschnitt „Portierte Formate“ aus `AppFormats.credits` (entfällt bei leerer Liste). Alle neuen Texte auf Deutsch und Englisch. Prüfen:
  - Die Szenarien „Über-Fenster öffnen“, „Portierte Formate“ und „Lizenztexte im Bundle“ der Spec `app-shell` sind erfüllt.
  - Ein Snapshot zeigt das Fenster auf Deutsch und Englisch, einmal mit Test-Adresse, einmal ohne.
  - Der Lokalisierungstest ist grün.

## 5. Regeln und Dokumentation

- [x] 5.1 `openspec/config.yaml` nach D6 ergänzen:
  - **GPSLoggerKitGPL:** neuer Abschnitt „GPSLoggerKitGPL (entschieden am 2026-11-10)“ mit Lizenz, Plattform, zulässigen Lizenzen, Leseregel, „kein Rückweg“, Dateikopf, Herkunft und der Zuordnungsliste der Familien. Umgesetzte Formate gehen an GPSLoggerKit. NAL bleibt Black-Box wegen der Lizenz von `wsg2000.c`. Die übrigen Familien sind offen.
  - **GPSLoggerKit:** Im Abschnitt GPSLoggerKit verweist die Clean-Room-Regel darauf.
  - **Vertrieb:** Die App steht unter GPL-3.0-or-later, das Quellcode-Angebot ist Pflicht.
  - **Regeln:** Proposal-Regel „Zuordnung der Familie festlegen“ und Design-Regel „Vorlagen mit Version, Lizenzzitat und Zeile nennen“.
  - Prüfen: `openspec validate --all --strict` meldet keine Fehler.
- [x] 5.2 `CLAUDE.md` nach D6 kurz ergänzen. Die README von GPSLoggerKit verweist im Clean-Room-Abschnitt auf GPSLoggerKitGPL als Ort für Portierungen, ohne die MIT-Regel aufzuweichen. Prüfen: Beide Texte stimmen mit `config.yaml` überein.

## 6. Abschluss

- [x] 6.1 `swift test` in GPSLoggerKit (macOS und iOS-27.1-Simulator), GPSLoggerKitGPL und GPSLoaderKit, dazu `xcodebuild test` für die App und `openspec validate gpl-driver-package --strict`. Prüfen: alles grün.
- [ ] 6.2 [manuell] Der Entwickler entscheidet die Bezugsquelle des Quellcodes (öffentliches Repository oder Archiv je Version auf der Website) und setzt `GPSLOADER_SOURCE_CODE_URL`. Dort liegen auch die Quellen von gpsbabel 1.7.0 und Qt 5.12.9. Prüfen: `verify-bundle.sh` ist für einen Release-Build grün, und der Link im Über-Fenster öffnet die Quelle.
