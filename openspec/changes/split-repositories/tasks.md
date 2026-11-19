# Tasks: split-repositories

Schritte mit „[Freigabe]“ sind von außen sichtbar und werden erst nach ausdrücklicher Freigabe des Entwicklers ausgeführt (D9).

## 1. Vorbereitung

- [ ] 1.1 Prüfen, dass `rename-and-icon` umgesetzt ist und `support-package`, `device-ports-and-hints` und `main-window-sections` archiviert sind. Prüfen: `openspec list` zeigt nur noch `split-repositories` als aktiven Change; `openspec validate --all --strict` ist grün.
- [ ] 1.2 Zweige `split/gpsloggerkit` und `split/gpsloggerkitgpl` mit `git subtree split` erzeugen (D1). Ihre Historie prüfen: nur Paketdateien, keine Binaries, im MIT-Zweig keine Dateien aus gpsbabel oder anderer GPL-Software, Fixtures nur mit synthetischen Orten. Prüfen: Der Bericht (Dateiliste über alle Commits) zeigt keine Treffer, und `swift build` und `swift test` sind in einem Checkout jedes Zweigs grün (für das GPL-Paket vorerst mit Pfad-Abhängigkeit).

## 2. Repository GPSLoggerKit

- [ ] 2.1 [Freigabe] Öffentliches Repository `mytracks/GPSLoggerKit` anlegen und `split/gpsloggerkit` als `main` pushen. Prüfen: `gh repo view mytracks/GPSLoggerKit` zeigt `PUBLIC`, und die Historie auf GitHub entspricht dem Zweig.
- [ ] 2.2 Im neuen Repository einrichten (D5, D6):
  - `openspec/` mit den Specs aus dem Proposal und einer `config.yaml` mit den MIT-Regeln;
  - `CLAUDE.md`, `.gitignore`;
  - README-Abschnitte zu Einbindung per URL, Lizenz und Herkunft, mit Verweis auf das gpsloader-Archiv.

  Prüfen: `openspec validate --all --strict` ist im neuen Repository grün.
- [ ] 2.3 Change `standalone-repository` im neuen Repository anlegen und umsetzen. Er passt „Eigenständigkeit“ mit dem Szenario „Herausgelöst bauen“ und den Purpose von `logger-kit` an (D5). Prüfen: Der Change ist archiviert, und die Specs enthalten keinen Verweis mehr auf `Packages/` oder das gpsloader-Repository.
- [ ] 2.4 `Scripts/release.sh <Version>` für das Paket mit Prüfungen, `swift test`, iOS-Simulator-Tests, Tag und GitHub-Release (D7) und `docs/releases/0.1.0.md`. Prüfen: Ein Lauf mit einer Probeversion bricht ohne Release-Notes ab, ebenso bei einem Tag, das es schon gibt. Ein Trockenlauf (`--dry-run`) zeigt die Befehle, ohne etwas zu veröffentlichen.
- [ ] 2.5 [Freigabe] GPSLoggerKit 0.1.0 veröffentlichen. Prüfen: Auf GitHub gibt es das Tag `0.1.0` und ein Pre-release mit den Release-Notes; ein leeres Testprojekt im Scratchpad bindet `https://github.com/mytracks/GPSLoggerKit.git` mit `.upToNextMinor(from: "0.1.0")` ein und baut für macOS und iOS.

## 3. Repository GPSLoggerKitGPL

- [ ] 3.1 [Freigabe] Öffentliches Repository `mytracks/GPSLoggerKitGPL` anlegen und `split/gpsloggerkitgpl` als `main` pushen. Prüfen: `gh repo view` zeigt `PUBLIC`.
- [ ] 3.2 `Package.swift` auf `.package(url: "https://github.com/mytracks/GPSLoggerKit.git", .upToNextMinor(from: "0.1.0"))` umstellen (D2). Prüfen: `swift build` und `swift test` sind in einem frischen Checkout grün.
- [ ] 3.3 Im neuen Repository einrichten (D5, D6):
  - `openspec/` mit den Specs aus dem Proposal und einer `config.yaml` mit den Portierungsregeln;
  - `CLAUDE.md`, README, `.gitignore`.

  Anschließend Change `standalone-repository` anlegen und umsetzen. Er passt „Plattform und Abhängigkeiten“ mit dem Szenario „Bauen mit GPSLoggerKit allein“, den Purpose von `logger-kit-gpl` und die gekürzten Device-Specs an. Prüfen: `openspec validate --all --strict` ist grün, und der Change ist archiviert.
- [ ] 3.4 `Scripts/release.sh <Version>` wie in 2.4, ohne iOS-Tests, mit `docs/releases/0.1.0.md`. Prüfen: wie in 2.4.
- [ ] 3.5 [Freigabe] GPSLoggerKitGPL 0.1.0 veröffentlichen. Prüfen: Tag und Pre-release `0.1.0` auf GitHub; `swift build` in einem frischen Checkout des Tags ist grün.

## 4. gpsloader umstellen

- [ ] 4.1 `Packages/GPSLoaderKit/Package.swift` auf beide URLs mit `.upToNextMinor(from: "0.1.0")` umstellen (D2). `Packages/GPSLoggerKit` und `Packages/GPSLoggerKitGPL` entfernen. Prüfen: `swift test` in `Packages/GPSLoaderKit` und `xcodebuild test` sind grün.
- [ ] 4.2 `Package.resolved` versionieren, `.gitignore` einschränken und das Übernehmen in `release.sh` ergänzen (D3, offene Frage XcodeGen klären). Prüfen: Ein Release-Build aus einem frischen Checkout löst genau die Versionen aus der versionierten Datei auf (Build-Log, `-onlyUsePackageVersionsFromResolvedFile`).
- [ ] 4.3 Über-Fenster: Quelle von GPSLoggerKit ist `https://github.com/mytracks/GPSLoggerKit` (D8). Prüfen: Snapshot des Über-Fensters (de/en); der Link öffnet das Repository.
- [ ] 4.4 `Scripts/release.sh --publish` mit den Prüfungen vor dem Build, Tag und `gh release create` (D7) und `docs/releases/0.1.0.md`. Prüfen:
  - Ohne Release-Notes bricht das Skript vor dem Build ab, ebenso bei vorhandenem Tag und mit `--publish --skip-notarize`.
  - Ohne `--publish` entsteht weder Tag noch Release.
  - Ein Trockenlauf zeigt die Befehle für Tag und Release.

## 5. OpenSpec und Dokumentation in gpsloader

- [ ] 5.1 `openspec/config.yaml` aufteilen (D6): App-Kontext, Vertrieb über GitHub-Releases, Verweise auf die Paket-Repositories, Regel „ein Change arbeitet in genau einem Repository“. Prüfen: Keine Regel steht doppelt oder fehlt; ein Abgleich mit der alten Datei ist im Commit beschrieben.
- [ ] 5.2 `CLAUDE.md` und `README.md`: Aufteilung der Repositories, lokaler Override (D4), Ablauf für paketübergreifende Änderungen, Releases. Prüfen: Die Befehle im README laufen in einem frischen Checkout.

## 6. Release

- [ ] 6.1 [Freigabe] myTracks Loader 0.1.0 mit `Scripts/release.sh --publish` veröffentlichen. Prüfen:
  - Auf GitHub gibt es das Pre-release `0.1.0` mit ZIP und Prüfsumme.
  - Das heruntergeladene ZIP besteht die Gatekeeper-Prüfung.
  - `Package.resolved` des Tags nennt `0.1.0` beider Pakete.
- [ ] 6.2 [manuell, Hardware] Der Entwickler lädt das Release-ZIP auf einem Apple-Silicon-Mac und einem Intel-Mac aus GitHub, startet die App und liest ein Gerät aus. Prüfen: Die App startet ohne Gatekeeper-Warnung, und das Auslesen gelingt.

## Workflow follow-up

- Nach dem Archivieren die Purpose-Texte der gekürzten Device-Specs in gpsloader anpassen (D5).
- In myTracks Neo einen eigenen Change zum Einbinden von GPSLoggerKit 0.1.0 anlegen.
