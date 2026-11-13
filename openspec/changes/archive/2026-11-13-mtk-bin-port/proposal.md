# Proposal: MTK-Speicherabbilder (mtk-bin, m241-bin) als Portierung in GPSLoggerKitGPL

## Why

Die verbreitetste Logger-Familie der Alt-App sind Geräte mit MediaTek-Chipsatz: iBlue 747, Qstarz BT-Q1000/BT-Q1300/BT-100, Holux M-241/GPSport 245 und weitere. Beim Auslesen schreibt gpsbabel ihren Speicher als `data.bin`. Die Variante „Holux GPSport 245 – alternative“ der Alt-App liest sogar ausdrücklich diese Datei mit `-i m241-bin` (`docs/legacy-analysis.md`, Abschnitt zum Holux-Ablauf). Der Dateimodus kann diese Abbilder bisher nicht lesen. Eine öffentliche Spezifikation des Logformats gibt es nicht. Am 2026-11-13 hat der Entwickler entschieden, alles Mögliche ins GPL-Paket zu portieren.

## What Changes

- **Neue Formate `mtk-bin` (MTK-Logger) und `m241-bin` (Holux M-241), Endung `.bin`,** in GPSLoggerKitGPL, nur macOS. Es ist eine Übersetzung des Dateilesers aus gpsbabel 1.7.0 (`mtk_logger.cc`, Formate `mtk-bin` und `m241-bin`) nach Swift.
  - Gelesen werden die Sektoren des Abbilds mit ihren Kopfdaten: Formatmaske, Aufzeichnungsgrund und Trennmarken.
  - Die Datensätze werden nach der Formatmaske dekodiert: Zeit, Gültigkeit, Position, Höhe, Geschwindigkeit, Kurs, DOP-Werte, Satelliten und weitere.
  - Prüfsummen werden geprüft.
  - Track-Aufteilung und Wegpunkte (Aufzeichnung per Taste) folgen der Vorlage.
- **Katalog und Herkunft:**
  - `GPLFileFormats.all` enthält beide Formate.
  - `credits` bekommt keinen neuen Eintrag, weil auch diese Vorlage von gpsbabel stammt. Die Urheberangabe des gpsbabel-Eintrags wird um die Autoren von `mtk_logger.cc` ergänzt.
  - `PROVENANCE.md` bekommt die Abschnitte `mtk-bin` und `m241-bin`.

## Zuordnung der Familie

- **Familie MTK:** GPSLoggerKitGPL (Portierung), Entscheidung des Entwicklers vom 2026-11-13. Sie ist schon in `openspec/config.yaml` eingetragen (Change `skytraq-bin-port`).
- **Vorlage:** gpsbabel, Tag `gpsbabel_1_7_0`, Datei `mtk_logger.cc`. Copyright (C) 2007 Per Borgentun, mit Teilen (C) 2006 Andy Armstrong. Lizenz GPL-2.0-or-later (`mtk_logger.cc`, Zeilen 8–11) und damit zulässig.
- **Leseregel:** Gelesen wird nur `mtk_logger.cc` und, soweit nötig, die dort benutzten gemeinsamen Hilfen von gpsbabel.

## Capabilities

### New Capabilities

- `mtk-import`: Speicherabbilder von MTK-Loggern (einschließlich Holux M-241) einlesen und daraus Tracks und Wegpunkte bilden.

### Modified Capabilities

- `logger-kit-gpl`: Der Katalog des Pakets enthält zusätzlich `mtk-bin` und `m241-bin`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Treiber `mtk`:** Blumax GPS-4044, iBlue 747, iTrek Z1, Networx iGeo, Photomate 887, QStarz BT-100, Qstarz BT-Q1000, Qstarz BT-Q1300 und Transystem 860E, jeweils über USB und Bluetooth.
- **Treiber `m241`:** Holux M-241, Holux GPSport 245 und „Holux GPSport 245 – alternative“.
- **Nur über eine Abbild-Datei:** Sie entsteht z. B. als `data.bin` beim Auslesen mit gpsbabel. Das direkte Auslesen ist nicht Teil dieses Changes.

## Nicht im Umfang

- **Direktes Auslesen und Löschen über die serielle Schnittstelle** (gpsbabel `mtk`, `m241`): Dafür fehlt die Treiber-Anbindung des GPL-Pakets, also ein eigener Change.
- **CSV-Ausgabe** (`csv=` der Vorlage) und die Option `block_size_kb`.
- **MediaTek Locus** (`mtk_locus`, eigenes Format eingebauter Module): Er gehört nicht zum Gerätekatalog.
- **iOS.**
- **Echte Abbilder als Fixtures:** Es gibt nur synthetische Abbilder, gegengeprüft mit dem gpsbabel-1.7.0-Binary.

## Impact

- **Neue Dateien:** `Packages/GPSLoggerKitGPL/Sources/GPSLoggerKitGPL/MTK/`, Lokalisierung der beiden Formatnamen, Tests mit einem Test-Encoder und eine Fixture.
- **App:** Ihr Code bleibt unverändert. Das Hauptfenster listet zwölf Formate.
- **Dokumentation:** `PROVENANCE.md` und `README.md` des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` (MTK: Dateiformat portiert) werden ergänzt.
