# Design: Paket für portierten GPL-Code

## Context

- **GPSLoggerKit** (MIT, macOS 12+ und iOS 27+) hat seinen Katalog als feste Liste `FileFormats.all`. Darauf arbeiten `FileFormats.format(withID:)`, `detect(prefix:fileName:)` und `read`/`readSynchronously`. Ein Test in `FileFormatTests.swift` prüft, dass jedes Format einen Abschnitt in `PROVENANCE.md` hat.
- **GPSLoaderKit** (macOS 12+) bindet GPSLoggerKit ein. `FileConversion/FileConverter.swift` ruft `FileFormats.detect` und `FileFormats.format(withID:)` direkt auf.
- **App:**
  - `App/ConversionPresenter.swift` listet die Formatnamen aus `FileFormats.all`.
  - `App/AboutWindowController.swift` zeigt gpsbabel und Qt mit Links auf ihre Quellen.
  - `project.yml` kopiert `Vendor/gpsbabel-1.7.0/Licenses` (GPL-2.0, GPL-3.0, LGPL-3.0) nach `Contents/Resources/Licenses`. `Scripts/verify-bundle.sh` prüft diese drei Texte.
- **Lizenzen:** Bisher gibt es nur `Packages/GPSLoggerKit/LICENSE` (MIT). Für das Repository, die App und GPSLoaderKit gibt es keine Lizenzdatei.
- **Alt-App:** Lizenzen und Herkunft der damaligen Fremdprogramme stehen in `docs/legacy-analysis.md`, Abschnitte 3 und 5.
  - `igotu2gpx`: GPL.
  - `rgm3800-rev25.py`: GPLv3.
  - `iTU4l`: GPLv2.
  - `myTracks/Source/Resources/wsg2000/wsg2000.c`: Zeilen 5–13. Das ist eine eigene „Attribution Share-Alike“-Lizenz mit Zusatzbedingungen. Eine GPLv2-Freigabe gibt es nur als Absicht.
  - Für diese Angaben wurden nur die Lizenzhinweise gelesen, kein Code.

## Goals / Non-Goals

**Goals:**
- Ein Ort für portierten Code, ohne GPSLoggerKit lizenzrechtlich zu berühren.
- Die App bezieht ihre Formate aus beiden Paketen, ohne dass künftige Formate die App ändern.
- Die Regeln für Portierungen sind eindeutig und für den Agenten prüfbar festgehalten.

**Non-Goals:**
- Portierte Formate oder Treiber. Der Katalog des neuen Pakets bleibt zunächst leer.
- Ein Treiberprotokoll für das GPL-Paket. Die Treiber-Abstraktion für das direkte Auslesen entsteht erst mit der ersten Gerätefamilie. Dann gilt dasselbe Muster wie für Formate (D2).
- iOS für das GPL-Paket.

## Decisions

### D1 Paket `GPSLoggerKitGPL`

- **Ort und Lizenz:** `Packages/GPSLoggerKitGPL`. `LICENSE` enthält den unveränderten GPL-3.0-Text, dieselbe Datei wie `Vendor/gpsbabel-1.7.0/Licenses/GPL-3.0.txt`. Die README nennt „GPL-3.0-or-later“.
- **Aufbau:**
  - Produkt und Target `GPSLoggerKitGPL`, Testtarget `GPSLoggerKitGPLTests`.
  - `platforms: [.macOS(.v12)]`, Swift 6 Language Mode.
  - Einzige Abhängigkeit: `.package(path: "../GPSLoggerKit")`.
- **Ressourcen:** Noch keine. `defaultLocalization` und `Resources/Localizable.xcstrings` kommen mit dem ersten Format. Ein leerer String-Katalog ergäbe nur Build-Warnungen.
- **Katalog:**
  - `public enum GPLFileFormats` mit `public static let all: [any FileFormat] = []`.
  - `public static let credits: [Credit] = []`. `Credit` ist ein `Sendable`-Struct mit `project`, `authors`, `license` und `sourceURL` und versorgt das Über-Fenster (D5).
- **iOS:** ausgeschlossen. Die GPL und die Bedingungen des App Store vertragen sich nicht. Formate, die auch unter iOS laufen sollen, gehören in GPSLoggerKit.
- **Alternative: ein zweites Target im Paket GPSLoggerKit.** Verworfen: GPSLoggerKit soll später als eigenes MIT-Repository ausgelagert werden. Ein GPL-Target darin würde jede Auslagerung und jede Prüfung der Lizenz unnötig erschweren.

### D2 Zusammensetzbarer Katalog in GPSLoggerKit

- **Neuer Typ** `public struct FormatCatalog: Sendable`:
  - `init(_ formats: [any FileFormat])` löst bei doppelter Kennung `precondition` aus.
  - Methoden `all`, `format(withID:)`, `detect(prefix:fileName:)`.
  - `static let standard = FormatCatalog(FileFormats.all)`.
  - `func adding(_ formats: [any FileFormat]) -> FormatCatalog`. Die neuen Formate stehen hinten, die eigenen Formate bleiben vorn.
- **Erkennung:** Die Logik aus `FileFormats.detect` zieht in `FormatCatalog.detect` um: erst Formate mit passender Endung, dann der Rest, jeweils in Katalogreihenfolge. `FileFormats.detect` und `FileFormats.format(withID:)` delegieren auf `.standard`. Damit bleibt die API unverändert.
- **Einlesen:** `FileFormats.read`/`readSynchronously` bekommen schon das Format als Wert und brauchen keine Änderung.
- **Neutralität:** GPSLoggerKit erwähnt das GPL-Paket weder im Code noch in der API-Dokumentation. Der Typ ist ein allgemeiner Erweiterungspunkt, auch für andere Apps.
- **Concurrency:** `FileFormat` ist `Sendable`, `[any FileFormat]` damit auch. `FormatCatalog` ist ein unveränderlicher Wert, `standard` eine `static let`. Es gibt keinen globalen veränderlichen Zustand und keine Registrierung zur Laufzeit.
- **Alternative: veränderliche globale Registrierung** wie `FileFormats.register(_:)`. Verworfen: Sie wäre globaler veränderlicher Zustand unter Strict Concurrency (Lock nötig), und das Ergebnis hinge von der Reihenfolge des Starts ab.

### D3 Katalog der App in GPSLoaderKit

- **Abhängigkeit:** `FileConversion` hängt zusätzlich von `GPSLoggerKitGPL` ab (`.package(path: "../GPSLoggerKitGPL")`).
- **Neuer Typ** `public enum AppFormats`:
  - `catalog = FormatCatalog.standard.adding(GPLFileFormats.all)`.
  - `credits = GPLFileFormats.credits`.
- **`FileConverter`:**
  - `plan(for:catalog:)` und `convert(_:catalog:referenceDate:)` bekommen den Parameter `catalog` mit dem Standardwert `AppFormats.catalog`. Tests übergeben einen Katalog mit Testformat.
  - Der Plan merkt sich nur Kennungen. Deshalb sucht `convert` die Formate im selben Katalog.
- **App:**
  - `ConversionPresenter` listet `AppFormats.catalog.all`.
  - Das Über-Fenster liest `AppFormats.credits`.
  - Die App bindet das GPL-Paket nicht direkt ein, nur über `FileConversion`. `project.yml` bleibt bei den Paketverweisen unverändert.

### D4 Lizenz von App und Repository

- **Wurzel des Repositorys:** `LICENSE` mit dem GPL-3.0-Text. Die README bekommt einen Abschnitt „Lizenz“:
  - Die App, GPSLoaderKit, RosettaInstaller und GPSLoggerKitGPL stehen unter GPL-3.0-or-later.
  - GPSLoggerKit steht unter MIT.
  - gpsbabel steht unter GPL-2.0-or-later, Qt unter LGPL-3.0.
- **Copyright:** `NSHumanReadableCopyright` bleibt „© 2026 Dirk Stichling“.
- **Dateiköpfe:** Eigene Dateien bekommen keinen Lizenzkopf. Ihre Lizenz ergibt sich aus der Lizenzdatei des Pakets bzw. des Repositorys.

### D5 Über-Fenster und Lizenztexte im Bundle

- **Neuer Abschnitt** über „Third-party software“: Die App steht unter der GPL Version 3 oder später, dazu ein Link „Source code“.
- **Adresse des Quellcodes:** kommt aus dem Info.plist-Schlüssel `GPSLoaderSourceCodeURL`. Xcode übernimmt über `INFOPLIST_KEY_…` nur bekannte Schlüssel. Deshalb setzt `project.yml` die Build-Einstellung `GPSLOADER_SOURCE_CODE_URL`, und eine Teil-Plist `App/Info.plist` mit nur `GPSLoaderSourceCodeURL = $(GPSLOADER_SOURCE_CODE_URL)` wird über `INFOPLIST_FILE` mit der erzeugten Plist zusammengeführt.
  - Ist der Wert leer, zeigt das Fenster den Lizenzsatz ohne Link.
  - `Scripts/verify-bundle.sh` schlägt dann für Release-Builds fehl. So kann keine Version ohne Quellcode-Angebot ausgeliefert werden.
  - Eine Adresse wird nicht erfunden. Der Entwickler setzt sie (Task 6.2).
- **Fremdkomponenten:**
  - GPSLoggerKit: „MIT License, © 2026 Dirk Stichling“ mit einem Button für den Lizenztext.
  - gpsbabel und Qt wie bisher.
  - Ist `AppFormats.credits` nicht leer, folgt „Portierte Formate“ mit je einer Zeile „Projekt – Urheber – Lizenz“ und einem Link auf die Quelle. Bei leerer Liste entfällt der Abschnitt.
- **Bundle:**
  - XcodeGen kann einzelne Dateien beim Kopieren nicht umbenennen. Deshalb liegt eine Kopie von `Packages/GPSLoggerKit/LICENSE` als `Vendor/Licenses/MIT-GPSLoggerKit.txt` im Repository, und `project.yml` kopiert den Ordner nach `Contents/Resources/Licenses`.
  - Ein Test in GPSLoaderKit vergleicht die Kopie mit dem Original, damit beide nicht auseinanderlaufen.
  - `verify-bundle.sh` prüft zusätzlich `MIT-GPSLoggerKit.txt` im Bundle.

### D6 Regeln für Portierungen

Die Regeln stehen in `openspec/config.yaml` (Abschnitt „GPSLoggerKitGPL“), kurz in `CLAUDE.md` und ausführlich in der README des Pakets.

1. **Zuordnung pro Familie:** Das Proposal jeder neuen Familie legt fest, ob sie Clean-Room in GPSLoggerKit oder als Portierung in GPSLoggerKitGPL entsteht. Das Ergebnis kommt in die Zuordnungsliste in `config.yaml`. Die bereits umgesetzten Formate (NMEA, GPX, IGC, FIT, TCX, Suunto, KML) sind GPSLoggerKit zugeordnet.
2. **Wann GPL-Quelltext gelesen werden darf:** nur in einem Change, dessen Proposal die Familie GPSLoggerKitGPL zuordnet, und nur für diese Familie. Bei Arbeit an GPSLoggerKit liest der Agent keinen GPL-Quelltext.
   - Muss für eine Portierung GPSLoggerKit selbst erweitert werden, etwa um eine neue Warnungsart, dann nur allgemein und ohne Code aus der Vorlage.
   - Im Zweifel gehören Hilfsfunktionen ins GPL-Paket.
3. **Kein Rückweg:** Ist eine Familie GPSLoggerKitGPL zugeordnet und ihr Quelltext gelesen, bleibt sie dort.
4. **Vereinbare Lizenzen:**
   - Zulässig sind GPL-2.0-or-later, GPL-3.0(-or-later), LGPL-2.1-or-later, CC BY-SA 4.0 sowie MIT, BSD, Apache 2.0 und Public Domain.
   - Nicht zulässig sind GPL-2.0-only, CC BY-SA bis 3.0, eigene Lizenzen und Quellen ohne Lizenz.
   - Das Design der Familie zitiert die Lizenzangabe der Vorlage mit Datei und Zeile.
5. **Version der Vorlage:** Bei gpsbabel gilt der Stand von Tag `gpsbabel_1_7_0`, weil das Verhalten zur mitgelieferten Binary passen soll. Neuere Stände sind nur erlaubt, wenn das Design das begründet. Quellen werden in den Scratchpad geladen, nicht ins Repository.
6. **Dateikopf portierter Dateien:**
   ```swift
   // Ported from <Projekt> <Pfad> (<Tag oder Commit>).
   // Original: Copyright (C) <Jahre> <Urheber>, <Lizenz der Vorlage>.
   // Translated to Swift and modified for gpsloader by Dirk Stichling, <JJJJ-MM-TT>.
   // SPDX-License-Identifier: GPL-3.0-or-later
   ```
7. **Herkunft:**
   - `PROVENANCE.md` des Pakets bekommt je Format einen Abschnitt mit Vorlagen, Lizenz, eigenen Ergänzungen und Black-Box-Prüfungen.
   - Ein Test wie in GPSLoggerKit erzwingt den Abschnitt.
   - Jedes Quellprojekt hat einen Eintrag in `credits`.

### D7 Tests

- **GPSLoggerKit:**
  - `FormatCatalog` mit einem Testformat (`FileFormatID("test-format")`, erkennt den Präfix `TESTFORMAT`):
    - Erkennung des Testformats.
    - NMEA bleibt erkannt.
    - Die eigenen Formate stehen vorn.
    - `standard.all` gleicht `FileFormats.all`.
  - Doppelte Kennungen: `precondition` lässt sich unter Swift Testing nicht abfangen. Deshalb wird eine interne Hilfsfunktion `duplicateIDs(in:)` getestet, auf die sich die `precondition` stützt.
- **GPSLoggerKitGPL:**
  - Keine Kennung von `GPLFileFormats.all` kommt in `FileFormats.all` vor.
  - `PROVENANCE.md` hat für jedes Format einen Abschnitt.
  - `credits` hat einen Eintrag je Quellprojekt. Mehrere Formate aus gpsbabel teilen sich einen Eintrag. Ein nicht leerer Katalog verlangt mindestens einen Eintrag, Einträge sind vollständig und nicht doppelt.
  - Die Lizenzdatei beginnt mit „GNU GENERAL PUBLIC LICENSE / Version 3“.
- **FileConversion:** Ein Test mit `AppFormats.catalog.adding([Testformat])` konvertiert eine Testdatei (Szenario „Format aus dem GPL-Paket“).
- **Concurrency und Abbruch:** Abbruch und Isolation ändern sich nicht. Der Katalog ist ein Wert, die Formate behalten ihre Abbruchprüfungen.

## Risks / Trade-offs

- **[Ansteckung des MIT-Pakets]** Wissen aus gelesenem GPL-Code könnte unbemerkt in GPSLoggerKit landen.
  - Gegenmittel: die Zuordnung pro Familie, die Regel „kein Rückweg“, kein GPL-Lesen bei Arbeit an GPSLoggerKit und die Herkunftsliste je Format.
  - Restrisiko: Der Agent hat zwischen Sitzungen kein Gedächtnis, innerhalb einer Sitzung schon. Deshalb arbeitet ein Change entweder an GPSLoggerKit oder an einer GPL-Portierung, nicht an beidem.
- **[Lizenz der App lässt sich schwer zurücknehmen]** Sobald portierter Code in der App ist, steht jede ausgelieferte Version unter der GPL. Solange GPSLoggerKitGPL leer ist, kann der Entwickler die Entscheidung noch ohne Folgen ändern.
- **[Quellcode-Angebot]** Ohne veröffentlichten Quellcode verletzt jede Auslieferung die GPL. Gegenmittel: Die Release-Prüfung in `verify-bundle.sh` schlägt ohne Adresse fehl (D5).
- **[Info.plist-Erweiterung]** Die App erzeugt ihre Info.plist bisher vollständig (`GENERATE_INFOPLIST_FILE`). Der zusätzliche Schlüssel braucht eine kleine Teil-Plist (`INFOPLIST_FILE` mit nur diesem Schlüssel), die Xcode mit der erzeugten zusammenführt. Das ist eine zusätzliche Datei, aber ohne Skript.
- **[Leeres Paket]** Bis zur ersten Portierung ist GPSLoggerKitGPL leer. Das ist gewollt: Die Struktur und die Regeln sind geprüft, bevor GPL-Code hineinkommt.

## Migration Plan

Additiv. Die bestehende API von GPSLoggerKit bleibt unverändert. `FileConverter` bekommt nur Parameter mit Standardwert. Ein Rückbau entfernt das Paket und die Abhängigkeit in `FileConversion`. Lizenzdateien und Regeln werden dann wieder auf den alten Stand gesetzt.

## Open Questions

- **Bezugsquelle des Quellcodes:** öffentliches Repository oder ein Archiv je Version auf der Website? Das entscheidet der Entwickler vor der ersten Auslieferung (Task 6.2). Für gpsbabel und Qt ist die eigene Kopie auf der Website seit `setup-foundation` offen und sollte dabei mit erledigt werden.
