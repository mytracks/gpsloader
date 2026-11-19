# Design: Pakete in eigene Repositories auslagern und Releases auf GitHub veröffentlichen

## Context

- **Pakete heute:** Sie liegen als `Packages/GPSLoggerKit` (MIT) und `Packages/GPSLoggerKitGPL` (GPL-3.0-or-later) im Repository `mytracks/gpsloader`.
  - Das GPL-Paket bindet GPSLoggerKit per `.package(path: "../GPSLoggerKit")` ein, GPSLoaderKit beide per Pfad.
  - Beide Pakete hängen von nichts anderem im Repository ab. Das sichern die Anforderungen „Eigenständigkeit“ (`logger-kit`) und „Plattform und Abhängigkeiten“ (`logger-kit-gpl`) mit Kopier-Szenarien ab.
- **Xcode-Projekt:** Es wird mit XcodeGen aus `project.yml` erzeugt und ist nicht versioniert. `Package.resolved` steht in `.gitignore`.
- **Release:** `Scripts/release.sh` baut, notarisiert und packt das ZIP. Es prüft, dass der Commit sauber und gepusht ist. Ein Tag oder GitHub-Release legt es nicht an.
- **Tests:** Das Testschema der App führt nur die Tests von GPSLoaderKit aus. Die Tests der beiden Pakete laufen mit `swift test` in ihren Ordnern.
- **GitHub:** Das Konto `mytracks` ist per `gh` angemeldet. `mytracks/gpsloader` ist öffentlich; die Pakete haben noch kein Repository.
- **myTracks Neo:** Es nutzt eigenes OpenSpec (`/Volumes/Dev/Projects/myTracksNeo/openspec`) und hat macOS und iOS 27 als Deployment Target. Es bindet nur GPSLoggerKit ein.

## Goals / Non-Goals

**Goals:**
- **Pakete per URL:** GPSLoggerKit lässt sich per URL und Version in myTracks Neo und in gpsloader einbinden.
- **Specs beim Code:** Jedes Repository trägt die Specs und Regeln, die zu seinem Code gehören.
- **Lizenzgrenze:** Die Trennung von MIT und GPL ist die Grenze der Repositories.
- **Reproduzierbar:** Releases sind reproduzierbar (feste Paketstände) und nachvollziehbar (Tags, Release-Notes, Quellcode zu jeder Version).
- **Veröffentlichen nur auf Ansage:** Nichts wird ohne ausdrücklichen Aufruf veröffentlicht.

**Non-Goals:**
- **Keine Verhaltensänderung:** Formate, Treiber und UI ändern sich nicht.
- **Keine Automatik:** keine automatischen Builds auf GitHub, keine Update-Prüfung in der App.
- **Kein Umbau von myTracks Neo:** Wie es das Paket einbindet, ist ein eigener Change dort.

## Decisions

### D1 Historie mit `git subtree split` übernehmen

Für jedes Paket entsteht ein Zweig nur mit der Historie seines Ordners:

```
git subtree split --prefix=Packages/GPSLoggerKit -b split/gpsloggerkit
```

Der Pfad wird dabei zum Wurzelverzeichnis. Der Zweig wird als `main` in das neue Repository gepusht.

Vor dem Push wird die Historie geprüft (`git log --name-only` über alle Commits des Zweigs):
- nur Dateien des Pakets;
- keine Binaries;
- keine Datei aus gpsbabel oder anderer GPL-Software im MIT-Repository;
- Fixtures nur mit synthetischen Orten.

Alternative „neu ohne Historie“: verworfen. Die Historie belegt den Clean-Room-Ablauf, auf den sich `PROVENANCE.md` stützt. Außerdem ist das gpsloader-Repository samt Historie schon öffentlich.

### D2 Namen, Orte und Abhängigkeiten

| Repository | Lizenz | Abhängigkeit |
|---|---|---|
| `mytracks/GPSLoggerKit` | MIT | keine |
| `mytracks/GPSLoggerKitGPL` | GPL-3.0-or-later | `.package(url: "https://github.com/mytracks/GPSLoggerKit.git", .upToNextMinor(from: "0.1.0"))` |
| `mytracks/gpsloader` | GPL-3.0-or-later | GPSLoaderKit: beide Pakete per URL, `.upToNextMinor(from: "0.1.0")` |

- **Versionsbereich:** `.upToNextMinor` setzt die Anforderung „Pakete in der App per Version“ um. Unter 1.0.0 darf eine neue Nebenversion Inkompatibles bringen, deshalb übernimmt die App 0.2.0 nur nach einer ausdrücklichen Änderung.
- **Lokale Ordner:** Die Repositories liegen nebeneinander unter `/Volumes/Dev/Projects/`, als `GPSLoggerKit/` und `GPSLoggerKitGPL/` neben `gpsloader/`.

### D3 Feste Paketstände trotz generiertem Projekt

- **Ablage:** `Package.resolved` wird für die App versioniert, und zwar als `Packages/GPSLoaderKit/Package.resolved` (aufgelöst von `swift package resolve` im Ordner). Der Eintrag in `.gitignore` wird dafür eingeschränkt.
- **Release-Build:** `release.sh` kopiert die Datei nach dem Erzeugen des Projekts nach `gpsloader.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Danach baut es mit `-onlyUsePackageVersionsFromResolvedFile`, sodass Xcode keine neueren Stände wählt.
- **Prüfung:** Ob XcodeGen die Datei direkt übernehmen kann, wird bei der Umsetzung geprüft. Dann entfällt die Kopie.

### D4 Lokal an Paket und App zugleich arbeiten

- **Xcode:** Der lokal ausgecheckte Paketordner wird ins Projekt gezogen. Xcode nutzt ihn dann an Stelle der URL (lokaler Override).
- **Kommandozeile:** `swift package edit GPSLoggerKit --path ../../../GPSLoggerKit` in `Packages/GPSLoaderKit`.
- **Dokumentation:** Beides steht im README.
- **Ablauf für Änderungen:** Ein Commit der App darf erst auf eine neue Paketfunktion bauen, wenn deren Version veröffentlicht ist. Die Reihenfolge ist:
  1. Change im Paket-Repository.
  2. Paket-Release.
  3. Change in gpsloader, der die Version anhebt.

### D5 OpenSpec aufteilen

- **Neue Repositories:** Jedes bekommt ein eigenes `openspec/` mit Schema `spec-driven`. Die Haupt-Specs werden unverändert kopiert; bei den gekürzten Device-Specs nur die Anforderungen, die umziehen (Zuordnung im Proposal).
  - **Danach je Repository ein erster Change `standalone-repository`.** Er passt alle Stellen an, die noch auf das gpsloader-Repository verweisen:
    - die Szenarien „Herausgelöst bauen“ und „Bauen mit GPSLoggerKit allein“: Bauen aus dem eigenen Repository bzw. mit GPSLoggerKit per URL;
    - die Purpose-Texte („das Swift-Paket von gpsloader“);
    - die Device-Specs: Was der Gerätekatalog der App verlangt, gehört nicht mehr dorthin.
  - So bleibt jede Änderung an Anforderungen ein Change, auch im neuen Repository.
- **gpsloader:**
  - Die Deltas dieses Changes legen die umgezogenen Capabilities still (`retire_capabilities: true`) bzw. kürzen sie auf die Katalog- und Transport-Anforderungen.
  - Die Purpose-Texte der gekürzten Specs kann ein Delta nicht ändern. Sie werden nach dem Archivieren von Hand angepasst: „Katalogeintrag … der App; das Protokoll liegt in GPSLoggerKitGPL“.
- **Archiv:** Die 25 archivierten Changes bleiben in gpsloader. Die README und `PROVENANCE.md` der Pakete verweisen auf `https://github.com/mytracks/gpsloader/tree/main/openspec/changes/archive`.
- **Alternative „zentraler OpenSpec-Store“:** verworfen. Die Specs lägen getrennt vom Code. MIT- und GPL-Planung lägen wieder zusammen. Außerdem müsste der Store auf jedem Rechner registriert werden.

### D6 `config.yaml` und `CLAUDE.md` aufteilen

| Repository | Kontext und Regeln |
|---|---|
| GPSLoggerKit | Produkt „Bibliothek“, Plattformen, MIT, Clean-Room-Regel mit zulässigen Quellen, Zuordnung der Clean-Room-Familien, Regeln für Specs, Designs (Quellen je Format nennen) und Tasks (Fixture-Tests) |
| GPSLoggerKitGPL | GPL, nur macOS, zulässige Lizenzen der Vorlagen, Dateikopf und `PROVENANCE.md`, „kein Rückweg“, gpsbabel-Tag `gpsbabel_1_7_0`, Zuordnung der portierten Familien |
| gpsloader | App, Vertrieb (GitHub-Releases), Leitplanken, Umfang, Diagnose; verweist für Formate und Treiber auf die beiden Repositories |

- **Regel in gpsloader:** Der Grundsatz „ein Change arbeitet an GPSLoggerKit-Formaten oder an einer Portierung, nicht an beidem“ wird hier zur Regel „ein Change arbeitet in genau einem Repository“.
- **Alt-Quellen:** Die Pakete brauchen die Alt-Quellen unter `gpsloader/input/mytracks4mac/` weiterhin. Ihr `CLAUDE.md` nennt dafür den Pfad `../gpsloader/input/mytracks4mac/` (nur lesen).
- **Bluetooth-Berechtigung:** Für das MIT-Repository gilt weiter, dass kein System-Dialog unaufgefordert ausgelöst wird.

### D7 Release-Skripte

**App (`Scripts/release.sh --publish`):**

Zusätzliche Prüfungen vor dem Build, damit ein Fehler nicht erst nach der Notarisierung auffällt:
- `gh` ist angemeldet.
- Es gibt `docs/releases/<Version>.md`.
- Das Tag `<Version>` existiert weder lokal noch auf `origin` (`git ls-remote --tags`).
- Es gibt kein Release dazu (`gh release view` schlägt fehl).

Nach erfolgreicher Notarisierung und Gatekeeper-Prüfung:
1. `git tag -a <Version> -m "<App-Name> <Version>"`.
2. `git push origin <Version>`.
3. `gh release create <Version> <ZIP> <ZIP>.sha256 --verify-tag --title "<App-Name> <Version>" --notes-file docs/releases/<Version>.md`, bei Version < 1.0.0 mit `--prerelease`.

Ohne `--publish` verhält sich das Skript wie bisher. `--publish` lässt sich nicht mit `--skip-notarize` oder `--allow-unpublished` kombinieren.

**Pakete (`Scripts/release.sh <Version>` im jeweiligen Repository):**
- Gleiche Prüfungen auf Stand, Tag, Release und Release-Notes (`docs/releases/<Version>.md`).
- Dann `swift test`. Bei GPSLoggerKit zusätzlich die Tests auf einem iOS-Simulator (`xcodebuild test -scheme GPSLoggerKit -destination 'platform=iOS Simulator,…'`).
- Danach Tag, Push und `gh release create … --verify-tag`, bei < 1.0.0 mit `--prerelease`.
- Die Pakete haben keine Versionsdatei, die Version ist allein das Tag.

**Reihenfolge des ersten Releases:**
1. GPSLoggerKit 0.1.0.
2. GPSLoggerKitGPL 0.1.0 (braucht 1.).
3. Die App 0.1.0 (braucht 1. und 2.).

### D8 Über-Fenster und Lizenzhinweise

- **Quelle von GPSLoggerKit:** Das Über-Fenster nennt `https://github.com/mytracks/GPSLoggerKit`.
- **Quelle der App:** Die Bezugsquelle der App bleibt `GPSLOADER_SOURCE_CODE_URL`.
- **Lizenztexte:** Sie kommen weiter aus `Vendor/Licenses`.
- **Prüfung:** `verify-bundle.sh` prüft unverändert.

### D9 Freigaben

Diese Schritte sind von außen sichtbar und werden einzeln vom Entwickler freigegeben. In den Tasks sind sie als „[Freigabe]“ markiert:
- ein Repository anlegen;
- den ersten Push in ein neues Repository;
- jedes Tag und jedes Release.

### Concurrency

Der Change ändert keinen Swift-Code mit eigener Isolation. Nur Abhängigkeiten und Skripte ändern sich. Die Pakete bauen weiter im Swift 6 Language Mode mit Strict Concurrency; die Tests in den neuen Repositories prüfen das.

## Risks / Trade-offs

- **Build braucht Netz:** Der erste Build nach einem frischen Checkout lädt die Pakete. → Release-Builds laufen ohnehin mit Netz (Notarisierung). Für die Entwicklung reicht der lokale Override.
- **Mehr Aufwand für übergreifende Features:** Ein neuer Treiber braucht zwei Changes und ein Paket-Release. → Das ist gewollt und entspricht der Nutzung durch myTracks Neo. Mit dem lokalen Override geht das Entwickeln trotzdem in einem Zug.
- **Tags sind öffentlich und dauerhaft:** Ein falsches Tag lässt sich nicht still korrigieren. → Das Skript prüft vorher, die Freigabe kommt vom Entwickler, Fehler behebt die nächste Patch-Version.
- **Specs verteilt:** Wer das Verhalten der App verstehen will, liest mehrere Repositories. → Die README und `config.yaml` von gpsloader verweisen auf die Paket-Repositories.
- **Identität der Pakete:** SwiftPM leitet sie aus dem letzten Teil der URL ab (`gpsloggerkit`). → Produktnamen und `package:`-Angaben bleiben `GPSLoggerKit` bzw. `GPSLoggerKitGPL`. Die Umstellung wird mit einem sauberen Build geprüft.

## Open Questions

- **Geklärt am 2026-11-19 (D3):** XcodeGen 2.46 schreibt keine `Package.resolved`. Deshalb kopiert `release.sh` die Datei von GPSLoaderKit in das erzeugte Projekt. Xcode 27.1 übernimmt sie trotz eines anderen `originHash` unverändert. Mit `-onlyUsePackageVersionsFromResolvedFile` bricht es ab (Exit 74, „out-of-date resolved file“), sobald ein Pin fehlt.
