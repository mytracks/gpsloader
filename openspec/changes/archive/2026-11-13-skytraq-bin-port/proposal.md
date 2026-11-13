# Proposal: SkyTraq-Speicherabbilder (skytraq-bin) als Portierung in GPSLoggerKitGPL

## Why

Logger mit SkyTraq-Venus-Chipsatz (Canmore GT-730FL/GT-740FL/GT-750F, Navin MiniHomer, Ventus G730 u. a.) liefern ihre Daten als binäres Speicherabbild. gpsbabel schreibt es beim Auslesen mit `dumpfile=` heraus, Hersteller-Software ebenso. Der Dateimodus kann solche Abbilder bisher nicht lesen. Eine öffentliche Beschreibung des Logformats (SkyTraq AN0008) ließ sich nicht beschaffen, ein Clean-Room-Import in GPSLoggerKit ist deshalb nicht möglich. Am 2026-11-13 hat der Entwickler entschieden: „Portieren alles, was möglich ist, in das GPL-Paket.“

## What Changes

- **Neues Format `skytraq-bin` (SkyTraq-Venus-Speicherabbild, Endung `.bin`)** in GPSLoggerKitGPL, nur macOS. Es ist eine Übersetzung des Dateilesers aus gpsbabel 1.7.0 (`skytraq.cc`, Format `skytraq-bin`) nach Swift.
  - Die Sektoren des Abbilds werden gelesen und ihre Einträge dekodiert: volle Positionsdatensätze, komprimierte Differenzdatensätze und POI-Markierungen.
  - Positionen werden aus den ECEF-Koordinaten nach WGS 84 umgerechnet, Zeiten aus GPS-Woche und Sekunde der Woche.
  - Die Track-Aufteilung folgt der Vorlage.
  - POI-Einträge ergeben Wegpunkte.
- **Gemeinsame Hilfen in GPSLoggerKitGPL:** Warnungen sammeln, Abbruch prüfen und lokalisierte Formatnamen (Deutsch, Englisch), soweit GPSLoggerKit sie nicht öffentlich anbietet. Es sind eigene Hilfen ohne Code aus der Vorlage.
- **Katalog und Herkunft:**
  - `GPLFileFormats.all` enthält `skytraq-bin`, und `GPLFileFormats.credits` nennt gpsbabel. Damit zeigt das Über-Fenster den Abschnitt „Portierte Formate“.
  - `PROVENANCE.md` des Pakets bekommt den Abschnitt `skytraq-bin`.
- **Zuordnung in `openspec/config.yaml`:**
  - Entscheidung des Entwicklers vom 2026-11-13: SkyTraq, Navilink/Locosys, MTK, Wintec, i-GotU und Medion GoPal entstehen als Portierung in GPSLoggerKitGPL.
  - NAL bleibt wegen der Lizenz von `wsg2000.c` ausgenommen.
  - V-900 und iBlue-CSV bleiben Clean-Room in GPSLoggerKit, weil sie bereits umgesetzt sind.

## Zuordnung der Familie

- **Familie SkyTraq:** GPSLoggerKitGPL (Portierung), Entscheidung des Entwicklers vom 2026-11-13.
- **Vorlage:** gpsbabel, Tag `gpsbabel_1_7_0`, Datei `skytraq.cc`. Copyright (C) 2008–2019 Mathias Adam. Lizenz GPL-2.0-or-later (`skytraq.cc`, Zeilen 11–14) und damit nach den Regeln des Pakets zulässig.
- **Leseregel:** Gelesen wird nur `skytraq.cc` und, soweit für das Verständnis nötig, die von dort benutzten gemeinsamen Hilfen von gpsbabel, nur für diese Familie.

## Capabilities

### New Capabilities

- `skytraq-import`: SkyTraq-Venus-Speicherabbilder einlesen und daraus Tracks und Wegpunkte bilden.

### Modified Capabilities

- `logger-kit-gpl`: Der Formatkatalog des Pakets enthält `skytraq-bin`, und `credits` nennt die Vorlage. Bisher war der Katalog leer.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Mittelbar alle Geräte mit Treiber `skytraq`:**
  - Canmore GT-730FL, GT-740FL und GT-750F;
  - Conrad GPS-Datenlogger GT-730 und GT-750;
  - Dörr GPS Photo Logger, Gisteq PhotoTrackr mini (DPL900), Navin MiniHomer;
  - SkyTraq Venus, Travel Honey, Ventus GPS Route Logger G730.
- **Nur über eine Abbild-Datei:** Ihr direktes Auslesen über USB-Seriell ist nicht Teil dieses Changes. Betroffen sind die Geräte, soweit ein Abbild als Datei vorliegt.

## Nicht im Umfang

- **Direktes Auslesen über die serielle Schnittstelle** (gpsbabel `skytraq`, `miniHomer`):
  - Dafür fehlt eine Treiber-Anbindung des GPL-Pakets an `LoggerCore`/`SerialTransport`, also eine Architekturentscheidung.
  - Ebenso fehlt die Gerätewahl in der App.
  - Das kommt in einen eigenen Change.
- **POI setzen oder Logger konfigurieren:** Diese Funktionen von `miniHomer` gehören nicht zum Dateimodus.
- **Optionen der Vorlage** wie `first-sector`/`last-sector`: Gelesen wird immer das ganze Abbild.
- **iOS:** Das GPL-Paket ist nur für macOS bestimmt.
- **Echte Abbilder als Fixtures:** Es gibt keine. Die Fixtures sind synthetisch und folgen dem Format der Vorlage. Zur Gegenprüfung liest das gpsbabel-1.7.0-Binary sie (`-i skytraq-bin`).

## Impact

- **Neue Dateien in `Packages/GPSLoggerKitGPL/Sources/GPSLoggerKitGPL/`:** `SkyTraq/` und gemeinsame Hilfen, dazu `Resources/Localizable.xcstrings`. In `Package.swift` kommen `defaultLocalization` und die Ressourcen dazu.
- **Tests:** synthetische Abbilder, die ein Test-Encoder erzeugt, dazu eine Black-Box-Gegenprüfung mit dem gpsbabel-Binary.
- **App:** Im Über-Fenster erscheint „Portierte Formate“ mit gpsbabel, und das Hauptfenster listet zehn Formate. Geändert wird nur das Layout dieser Zeile im Über-Fenster: Der Text bricht um, der Button steht darunter, weil die echte Zeile breiter ist als das Fenster. GPSLoggerKit bleibt unverändert.
- **Dokumentation:** `PROVENANCE.md`, `README.md` und Tests des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` werden ergänzt.
