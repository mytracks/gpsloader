# Design: SkyTraq-Speicherabbilder (Portierung)

## Context

- **GPSLoggerKitGPL** ist angelegt (Change `gpl-driver-package`), sein Katalog ist leer. Es hängt nur von GPSLoggerKit ab und kann nur dessen öffentliche API nutzen:
  - `FileFormat`, `ImportResult`, `ImportWarning` (öffentlicher Initialisierer), `GPSLoggerError` und das Datenmodell;
  - **nicht** nutzbar sind die internen Hilfen `WarningCollector`, `CancellationCheck`, `LocalizedStrings`, `baseName(ofFile:)` und `UTCTime`.
- **Wochenüberlauf:** `FileFormats.readSynchronously` wendet nach dem Lesen `RecordingProcessing.correctingWeekRollover` an. Es addiert 1024 Wochen, solange eine Zeit mehr als 512 Wochen vor dem Referenzdatum liegt.
- **App:** Sie setzt den Katalog aus `FormatCatalog.standard.adding(GPLFileFormats.all)` zusammen. Das Über-Fenster zeigt „Portierte Formate“, sobald `credits` Einträge hat.
- **Alt-App:** Sie las SkyTraq-Logger über gpsbabel (`skytraq`, siehe `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist` und `DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`). Ein eigener Dateileser existierte nicht.

## Goals / Non-Goals

**Goals:**
- `skytraq-bin` liefert für dieselben Abbilder dieselben Punkte, Zeiten, Höhen und Geschwindigkeiten wie gpsbabel 1.7.0. Erlaubt sind die in D4 genannten Verbesserungen.
- Die gemeinsamen Hilfen des GPL-Pakets taugen auch für die folgenden Portierungen (MTK, Wintec, Locosys, GoPal).

**Non-Goals:**
- Der serielle Treiber und die Optionen `first-sector`, `last-sector`, `gps-utc-offset` und `gps-week-rollover` der Vorlage.
- Änderungen an GPSLoggerKit.

## Decisions

### D1 Vorlage und Lizenz

- **Vorlage:** gpsbabel, Tag `gpsbabel_1_7_0`, Datei `skytraq.cc`.
  - Bezogen als `https://github.com/GPSBabel/gpsbabel/archive/refs/tags/gpsbabel_1_7_0.tar.gz` am 2026-11-13, SHA-256 `30b186631fb43db576b8177385ed5c31a5a15c02a6bc07bae1e0d7af9058a797`.
  - Die Datei liegt nur im Scratchpad.
- **Urheber und Lizenz:**
  - `skytraq.cc` Zeile 5: „Copyright (C) 2008-2019 Mathias Adam“. Die Zeilen 7–9 nennen J.C Haessig und Josef Reisinger als weitere Bearbeiter.
  - Zeilen 11–14: „either version 2 of the License, or (at your option) any later version“, also GPL-2.0-or-later und damit zulässig.
- **Übersetzt werden:**
  - die Konstanten (Zeilen 36–39);
  - `me_read32` (580–583), `gpstime_to_timet` (585–638) und `ECEF_to_LLA` (640–664);
  - die Eintragsformate (709–767), `process_data_item` (769–910), `process_data_sector` (912–927) und `file_read` (1385–1418).
- **Nicht übernommen werden:** der serielle Teil (Zeilen 147–575 und 929–1366) und die Optionen.
- **Gemeinsame Hilfen:** `be_read16` aus `util.cc` (Zeilen 565–569) ist eine triviale Big-Endian-Leseoperation. Sie wird nicht übersetzt, sondern als eigene Hilfe geschrieben.
- **Dateikopf** jeder portierten Datei nach Regel 6 des Paket-README.

### D2 Gemeinsame Hilfen (eigener Code)

Interne Datei `Sources/GPSLoggerKitGPL/Support/ImportSupport.swift`, ohne Code aus einer Vorlage:
- `Warnings`: sammelt Warnungen je Art mit Anzahl und erster Stelle und liefert `[ImportWarning]`, wie `WarningCollector` in GPSLoggerKit.
- `Cancellation`: prüft alle n Arbeitsschritte `Task.checkCancellation()`.
- `trackName(ofFile:)`: Dateiname ohne Verzeichnis und Endung.
- `ByteReader`: liest `UInt8`, `UInt16` (Big und Little Endian) und `UInt32` an einem Offset mit Bereichsprüfung, über `Data.withUnsafeBytes` ohne Kopien.
- `GPSTime.date(week:secondOfWeek:reference:)`: GPS-Zeit nach UTC.
  - Die Schaltsekunden kommen als Tabelle aus den öffentlichen IERS-Bulletins: 1999-01-01 13 s, 2006 14 s, 2009 15 s, 2012-07-01 16 s, 2015-07-01 17 s, 2017-01-01 18 s.
  - Der Wochenzyklus wird gewählt wie in D4.
- `L10n.string(_:)`: lokalisierte Texte aus `Bundle.module`. Dazu kommen `Resources/Localizable.xcstrings` und `defaultLocalization: "en"` in `Package.swift`.

- **Alternative:** die internen Hilfen von GPSLoggerKit öffentlich machen. Verworfen: Dieser Change soll GPSLoggerKit nicht ändern, siehe die Regel „ein Change arbeitet entweder an GPSLoggerKit-Formaten oder an einer Portierung“. Ein späterer Clean-Room-Change kann es in allgemeiner Form nachholen.

### D3 Leser

`SkyTraqBinFileFormat` (Kennung `skytraq-bin`, Endung `bin`, Name `format.skytraq-bin`: „SkyTraq-Speicherabbild“ bzw. „SkyTraq memory dump“) in `Sources/GPSLoggerKitGPL/SkyTraq/`:
- **Sektoren:** `read` zerlegt jedes Abbild in Sektoren zu 4096 Byte, der letzte darf kürzer sein. Je Sektor werden Einträge gelesen, bis `0xFF` oder das Ende erreicht ist.
- **Ende des Abbilds:** Endet die Verarbeitung eines Sektors mehr als 18 Byte (`FULL_ITEM_LEN`) vor dem Ende, ist das Abbild zu Ende. Das entspricht `file_read` mit `last-sector` = -1.
- **Typ und Geschwindigkeit:** Der Typ ist `byte0 >> 4`. Die Geschwindigkeit sind 12 Bit aus `(byte0 & 0x0F) << 8 | byte1` in km/h.
- **Byte-Reihenfolge** („middle endian“, wie `me_read32`): Aus `p[0..3]` wird `(p[2] << 24) | (p[3] << 16) | (p[0] << 8) | p[1]`.
- **Voll (`0x4`) und POI (`0x6`):** Zeit `ts` (Woche `ts & 0x3FF`, Sekunde `ts >> 12`), dann X, Y und Z als `Int32`. Der Zustand (Woche, Sekunde, X, Y, Z) wird gesetzt.
- **Komprimiert (`0x8`):**
  - `dt` sind 16 Bit Big Endian.
  - `dx = p[0] << 2 | p[1] >> 6`, `dy = (p[1] & 0x3F) | (p[2] & 0xF0) << 2`, `dz = p[3] | (p[2] & 0x03) << 8` über `dpos[0..3]`. Werte über 511 werden zu `511 - v`.
  - Sekunde, X, Y und Z werden um die Werte erhöht.
- **Hohe Rate (`0x2`) und POI (`0xC`):**
  - Woche `(byte0 & 0x03) << 8 | byte1`, Geschwindigkeit 16 Bit Big Endian.
  - `ts`, Breite, Länge und Höhe in der Byte-Reihenfolge oben. `ts & 0x3FFFFFFF` sind Millisekunden.
  - Breite und Länge mal 2⁻²⁰, Höhe mal 2⁻⁷.
- **ECEF nach WGS 84:** geschlossene Bowring-Näherung wie `ECEF_to_LLA`, mit a = 6 378 137 m und b = 6 356 752,31424518 m.
- **Punkt:** Ein Punkt hat Position, Höhe (Ellipsoid), Zeit und Geschwindigkeit in m/s (km/h / 3,6). Eine Markierung ergibt zusätzlich einen Wegpunkt `POI n`.
- **Track:** einer pro Abbild, benannt nach der Datei (D2).
- **Abbruch:** `Cancellation` je Eintrag.

### D4 Abweichungen von der Vorlage (bewusst)

- **Fehler:**
  - Die Vorlage bricht bei einem unbekannten Typ oder einem zu kurzen Eintrag mit `fatal` ab. Hier endet das Abbild an dieser Stelle mit der Warnung `truncatedFile` (Spec „Fehlerhafte Abbilder“).
  - Ein komprimierter Eintrag ohne vorherigen vollen Eintrag wird als `malformedRecord` verworfen. Die Vorlage würde vom Erdmittelpunkt aus rechnen.
- **Hohe Rate:**
  - Die Vorlage teilt die Millisekunden ganzzahlig durch 1000. Hier bleiben sie erhalten, sonst hätten Punkte mit 5 oder 10 Hz dieselbe Zeit.
  - POI-Einträge mit hoher Rate (`0xC`) ergeben in der Vorlage keinen Wegpunkt, weil die Bedingung nur für volle und komprimierte Längen gilt. Hier ergeben sie einen.
  - Nach einem Eintrag mit hoher Rate setzt die Vorlage den ECEF-Zustand nicht. Ein folgender komprimierter Eintrag bezieht sich dann auf den letzten vollen Eintrag. Das bleibt wie in der Vorlage, weil es ohne echte Abbilder keinen Anhaltspunkt für ein anderes Verhalten gibt.
- **Namen:**
  - Der Track heißt nach der Datei statt „SkyTraq tracklog“, wie bei allen Formaten von gpsloader.
  - Wegpunkte heißen `POI n` statt `TPnnnn`, wie bei der V-900.
- **Wochenzyklus:**
  - Die Vorlage wählt ihn relativ zur aktuellen Uhrzeit: Liegt die Woche über der aktuellen Woche modulo 1024, gilt der vorige Zyklus.
  - Das wird übernommen, mit einem Referenzdatum als Parameter, für Tests (Standard: jetzt).
  - Weil die Zeiten danach in den 1024 Wochen vor dem Referenzdatum liegen, verändert die nachgelagerte Korrektur von GPSLoggerKit sie nicht.

### D5 Erkennung

`matches(prefix:)`:
- Bis zum ersten `0xFF` oder zum Ende des Prefix müssen alle Einträge einen der Typen `0x2`, `0x4`, `0x6`, `0x8` oder `0xC` haben. Nur ein Eintrag am Ende des Prefix darf abgeschnitten sein.
- Der erste Eintrag muss voll oder mit hoher Rate sein, nicht komprimiert.
- Für den ersten vollen Eintrag gilt: √(X² + Y² + Z²) liegt zwischen 6 300 000 und 6 450 000 m. Bei hoher Rate gilt stattdessen |Breite| ≤ 90 und |Länge| ≤ 180.
- Ein Prefix aus lauter `0xFF` passt nicht.
- FIT (`.FIT` ab Byte 8), ZIP, XML und Text scheitern an Typ oder Radius. Die Formate von GPSLoggerKit stehen im Katalog vorn. Ein SkyTraq-Abbild passt zu keinem von ihnen, weil es binär ist und keine bekannte Signatur hat.

### D6 Concurrency

- `SkyTraqBinFileFormat` ist ein zustandsloser `Sendable`-Werttyp, der Leser ist ein lokaler Werttyp.
- Es gibt keine geteilten veränderlichen Daten und keinen Zugriff auf die Uhr außer dem Standardwert des Referenzdatums.
- Abbruch über `Cancellation` (D2).

### D7 Tests und Gegenprüfung

- **Test-Encoder:** `SkyTraqTestDump` im Testziel schreibt volle, komprimierte und POI-Einträge sowie solche mit hoher Rate, umgekehrt zu D3. Die Umrechnung WGS 84 nach ECEF dafür ist die Standardformel.
- **Fixture:** `Fixtures/venus.bin` entsteht mit dem Encoder. Sie hat zwei Sektoren, der zweite ist gefüllt bis kurz vor dem Ende; dazu einen dritten leeren Sektor und einen vierten mit Daten, die nicht gelesen werden dürfen. Die Koordinaten sind erfunden und liegen um 50° N, 8° O.
- **Black-Box:** Das gpsbabel-1.7.0-Binary liest `venus.bin` (`-i skytraq-bin -f venus.bin -o gpx`). Punktanzahl, Positionen (auf 10⁻⁶°), Höhen (auf 0,1 m), Zeiten und Geschwindigkeiten werden verglichen. Das Ergebnis kommt nach `PROVENANCE.md`.

## Risks / Trade-offs

- **Keine echten Abbilder:** Die Fixtures folgen der Vorlage, nicht beobachteten Geräten. → Die Black-Box-Prüfung stellt Gleichheit mit gpsbabel her, das seit Jahren mit echten Geräten genutzt wird. Dazu kommt der Hardware-Test (Task 6.2).
- **Schaltsekunden nach 2017:** Bisher ist keine weitere angekündigt. → Die Tabelle steht an einer Stelle und ist kommentiert.
- **Erkennung von `.bin`:** MTK- und Wintec-Abbilder folgen in späteren Changes und teilen die Endung. → Die Erkennung prüft Typen und Radius. Spätere Changes testen gegen die SkyTraq-Fixture.

## Migration Plan

Entfällt. Rückbau: `SkyTraqBinFileFormat` aus `GPLFileFormats.all` entfernen.
