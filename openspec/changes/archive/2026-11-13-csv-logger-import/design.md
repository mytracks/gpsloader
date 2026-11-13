# Design: CSV-Logger-Dateien (Columbus V-900, iBlue 747/757)

## Context

GPSLoggerKit hat den Formatvertrag `FileFormat` (`matches(prefix:)` auf die ersten 4096 Byte, `read(_:)`). Dazu gibt es `TextLines.forEachLine` für Textformate (LF, CR, CRLF), den `WarningCollector`, `CancellationCheck` und `baseName(ofFile:)`. IGC zeigt das Muster für ein Textformat mit einem Track pro Datei, das hier übernommen wird. Neue Formate kommen in `FileFormats.all`, und der vorhandene Provenance-Test verlangt für jedes Format einen Abschnitt in `PROVENANCE.md`.

So arbeitete die Alt-App: Sie las beide Gerätegruppen über gpsbabel, siehe `GPSBabel.m` in `input/mytracks4mac/DsTrackFramework/Source/Classes/GPSBabel/` mit dem Treiberwert `v900` aus `myTracks/Source/Resources/gpslogger.plist`. Eigenen Code für diese Formate gibt es in myTracks nicht. Die iBlue-CSV kam in der Alt-App nicht vor, sie ist eine Erweiterung aus `openspec/config.yaml`.

## Goals / Non-Goals

**Goals:**
- V-900 im einfachen und im professionellen Modus sowie die beiden iBlue-CSV-Varianten auf macOS und iOS lesen, ohne gpsbabel.
- Für die synthetischen Fixtures stimmen Punkte, Zeiten, Höhen, Geschwindigkeiten und Fix-Art mit gpsbabel 1.7.0 überein (Black-Box).

**Non-Goals:**
- Ein allgemeiner CSV-Leser mit Anführungszeichen und Escape-Regeln (RFC 4180). Keines der beiden Formate setzt Felder in Anführungszeichen.
- Fixe Spaltenbreiten wie bei gpsbabel. Gelesen wird am Komma, nicht an Byte-Positionen.

## Decisions

### D1 Quellen und Clean-Room

Die Familie entsteht Clean-Room in GPSLoggerKit. Gelesen werden kein GPL-Quelltext und keine Formatbeschreibung aus dem gpsbabel-Projekt (auch nicht `htmldoc`).

Grundlagen:
- **Bedienungsanleitung der Columbus V-900** (manualslib.com, Seite 9 „Track Log“): Der Logger zeichnet „date, time, latitude, longitude, altitude, speed, direction, voice, positioning mode, positioning type, PDOP, HDOP, VDOP“ auf, standardmäßig einmal pro Sekunde.
- **OpenStreetMap-Wiki**, Seiten „Columbus“ und „Visiontac VGPS-900“. Dort steht, dass die Logs CSV-Dateien „with fixed-length \x0-terminated fields“ sind. Die Kopfzeile enthält `INDEX`, `TAG`, `N/S`, `E/W` und `VOX`, Sprachaufnahmen liegen als `VOX<n>.WAV` daneben. Übernommen werden nur diese Fakten, kein Text und kein Skript.
- **Die Dateien selbst:** Beide Formate nennen ihre Spalten in der Kopfzeile.
- **Black-Box, gpsbabel-1.7.0-Binary aus dem App-Bundle, am 2026-11-13:**
  - `-i v900` mit synthetischen Dateien:
    - Der einfache Modus (`INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT,SPEED,HEADING,VOX`) mit NUL-gefüllten Feldern und CRLF wird gelesen.
    - Datum `JJMMTT` und Zeit `hhmmss` werden als UTC übernommen, `N/S` und `E/W` hängen an der Zahl, `SPEED` ist km/h (10 km/h ergeben 2,777778 m/s), `HEADING` ist der Kurs.
    - Zeilen mit `TAG` `C` und `V` ergeben einen Trackpunkt und zusätzlich einen Wegpunkt. Bei `V` heißt er `VOX00003.WAV`.
    - Im professionellen Modus (`…,FIX MODE,VALID,PDOP,HDOP,VDOP,VOX`) ergeben `3D` bzw. `2D` die Fix-Art. gpsbabel prüft die Zeilenlänge: Mit den Feldbreiten 6, 1, 6, 6, 10, 11, 5, 4, 3, 4, 5, 4, 4, 4, 9 werden die Zeilen angenommen.
  - `-o iblue747` und `-o iblue757` aus einer synthetischen GPX-Datei:
    - Die Kopfzeile lautet `INDEX,RCR,DATE,TIME,VALID,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT,SPEED,HEADING,DSTA,DAGE,PDOP,HDOP,VDOP,NSAT (USED/VIEW),SAT INFO (SID-ELE-AZI-SNR),DISTANCE,` mit abschließendem Komma.
    - Das Datum ist `2026/11/02` (747) bzw. `02/11/2026` (757), die Zeit `12:00:00`.
    - `VALID` ist `3d` oder `Unknown`, `SPEED` ist km/h (1,5 m/s ergeben `5.4`), die Höhe ganzzahlig in Metern.
    - Unbekannte DOP-Werte stehen als `0.000000`, eine unbekannte Satellitenzahl als `-1(`.
    - Westliche Längen schreibt gpsbabel mit Minus *und* `W` (`-8.000456,W`).
  - `-i iblue747`:
    - Diese Längen liest gpsbabel als -8,000456°.
    - `DGPS` ergibt `dgps`, `2d` ergibt `2d`, `No Fix` ergibt keine Fix-Art.
    - `RCR` = `B` ergibt keinen Wegpunkt.
    - Die Spalten liest gpsbabel an fester Position, die Kopfzeile wertet es nicht aus.

### D2 Gemeinsamer Zeilenleser

Interner Typ `CSVRecords` in `Formats/CSV/CSVRecords.swift`:
- **Zeilen:** Zerlegt wird mit `TextLines.forEachLine` ohne Filter. Ein UTF-8-BOM am Dateianfang wird entfernt.
- **Felder:** Jede Zeile wird an `,` getrennt. Jedes Feld wird von Leerzeichen, Tabulatoren und NUL befreit.
- **Leere Zeilen:** Zeilen, deren Felder danach alle leer sind, werden übersprungen.
- **Kopfzeile:** Die erste nicht leere Zeile ist die Kopfzeile. Ein leeres letztes Feld (abschließendes Komma) wird verworfen. `column(named:)` liefert den Index zu einem Namen, ohne Rücksicht auf Groß- und Kleinschreibung.
- **Datenzeilen:** Sie gehen mit 1-basierter Zeilennummer und Feldern an einen Closure. Ein Feld jenseits des Zeilenendes gilt als leer.
- **Zahlen:** `Double(_:)` auf dem getrimmten Feld. Ein leeres Feld ergibt `nil`.

- **Alternative:** byteweise mit festen Spaltenbreiten wie gpsbabel. Verworfen, weil die Breiten nur beobachtet, nicht beschrieben sind und Dateien anderer Firmware-Stände abweichen könnten.
- **Alternative:** ein vollständiger RFC-4180-Leser. Verworfen, siehe Non-Goals.

### D3 V-900

`V900FileFormat` (Kennung `v900`, Endung `csv`, Name `format.v900`: „Columbus V-900“):

- **Kopfzeile:** Die ersten sechs Spalten müssen `INDEX`, `TAG`, `DATE`, `TIME`, `LATITUDE N/S` und `LONGITUDE E/W` sein. Sonst wirft `read` `GPSLoggerError(.malformed(line: 1))`. Die übrigen Spalten werden über ihren Namen gesucht: `HEIGHT`, `SPEED`, `HEADING`, `FIX MODE`, `VALID`, `PDOP`, `HDOP`, `VDOP` und `VOX`.
- **Datum und Zeit:**
  - `DATE` hat genau sechs Ziffern, als `20JJ-MM-TT`. `TIME` hat genau sechs Ziffern, mit Stunde < 24, Minute < 60 und Sekunde < 60.
  - Umgerechnet wird über `UTCTime.days` bzw. `UTCTime.date`. Ein ungültiger Monat oder Tag ergibt `nil`.
- **Position:** Die Zahl ohne den letzten Buchstaben, der `N`, `S`, `E` oder `W` sein muss. `S` und `W` machen den Wert negativ.
  - Fehlt der Buchstabe oder ist die Zahl nicht lesbar, wird die Zeile als `malformedRecord` gezählt.
  - Liegt der Betrag über 90 bzw. 180, wird sie als `invalidCoordinate` gezählt.
- **Werte:**
  - `HEIGHT` ist die Höhe in Metern.
  - `SPEED` ist km/h; geteilt durch 3,6 ergibt es m/s.
  - `HEADING` ist der Kurs, sofern im Bereich 0–360.
  - Die Fix-Art: `DGPS` in `VALID` ergibt `dgps`, sonst ergibt `FIX MODE` `2D` bzw. `3D` die Fix-Art `2d` bzw. `3d`.
  - `PDOP`, `HDOP` und `VDOP` werden übernommen, wenn sie größer als 0 sind.
- **Markierungen:**
  - `TAG` `C` oder `D` ergibt einen Wegpunkt `POI <n>`; `n` zählt die Markierungen der Datei ab 1, Sprachaufnahmen mitgezählt.
  - `V` ergibt einen Wegpunkt `<VOX>.WAV`. Hat `VOX` schon eine Endung, bleibt der Name, wie er ist. Ist `VOX` leer, heißt der Wegpunkt `POI <n>`.
  - Andere Werte (`T`, `G` …) ergeben nur einen Trackpunkt.
  - Der Wegpunkt übernimmt Position, Zeit, Höhe und Qualität des Trackpunkts.
- **Track:** Ein Track pro Datei mit einem Segment, benannt nach `baseName(ofFile:)`.

### D4 iBlue-CSV

`IBlueCSVFileFormat` (Kennung `iblue-csv`, Endung `csv`, Name `format.iblue-csv`: „iBlue-CSV (747/757)“):

- **Kopfzeile:**
  - Die erste Spalte muss `INDEX` heißen. Pflicht sind die Spalten `DATE`, `TIME`, `LATITUDE`, `N/S`, `LONGITUDE` und `E/W`. Fehlt eine, wirft `read` `GPSLoggerError(.malformed(line: 1))`.
  - Wahlweise kommen `VALID`, `HEIGHT`, `SPEED`, `HEADING`, `PDOP`, `HDOP` und `VDOP` dazu, außerdem die erste Spalte, deren Name mit `NSAT` beginnt.
- **Datum:**
  - Drei Teile, getrennt durch `/`. Hat der erste Teil vier Ziffern, gilt `JJJJ/MM/TT`; hat der letzte vier, gilt `TT/MM/JJJJ`.
  - Andere Formen sind `malformedRecord`. `MM/TT/JJJJ` wird nicht unterstützt, siehe Risiken.
- **Zeit:** `hh:mm:ss` mit optionalem Bruchteil `.f…`, gerundet auf Millisekunden.
- **Position:**
  - Der Betrag des Zahlenwerts. `N/S` = `S` und `E/W` = `W` machen ihn negativ.
  - Andere Buchstaben als `N`/`S` bzw. `E`/`W` ergeben `malformedRecord`. Ein Betrag über 90 bzw. 180 ergibt `invalidCoordinate`.
- **Werte:**
  - `HEIGHT` in Metern, `SPEED` in km/h, `HEADING` im Bereich 0–360.
  - `VALID` (ohne Rücksicht auf Groß- und Kleinschreibung): `2d`, `3d` und `dgps` ergeben die Fix-Art, alle anderen Werte ergeben keine.
  - Die DOP-Werte werden übernommen, wenn sie größer als 0 sind.
  - `NSAT`: die führenden Ziffern, sofern das Feld nicht mit `-` beginnt.
- **Track:** wie bei D3. Wegpunkte gibt es nicht.

### D5 Erkennung

`matches(prefix:)` nimmt die erste nicht leere Zeile des Prefix, entfernt BOM und Füllbytes und vergleicht die getrimmten, großgeschriebenen Felder:
- **`v900`:** Die ersten sechs Felder sind genau die sechs Pflichtspalten aus D3.
- **`iblue-csv`:** Das erste Feld ist `INDEX`, und alle Pflichtspalten aus D4 sind vorhanden.
- **Ausschluss:** Eine V-900-Kopfzeile enthält weder `LATITUDE` noch `N/S` als eigene Spalte. Die beiden Regeln schließen sich also aus, und die Reihenfolge im Katalog spielt keine Rolle.

### D6 Fehler und Warnungen

- **Malformed:** Eine Datenzeile mit ungültigem Datum, ungültiger Zeit oder nicht lesbarer Position ergibt `malformedRecord` mit der Zeilennummer des ersten Falls.
- **Ungültige Koordinate:** Eine Position außerhalb des Bereichs ergibt `invalidCoordinate`.
- **Unlesbare Werte:** Höhe, Geschwindigkeit, Kurs und DOP, die sich nicht lesen lassen, fehlen einfach, ohne Warnung. So verhält sich auch gpsbabel bei leeren Feldern.
- **Leere Datei:** Eine Datei mit Kopfzeile, aber ohne gültige Zeile, ergibt keinen Track. `FileFormats.readSynchronously` meldet dann `.noUsableData`.
- **Fehlende Kopfzeile:** Eine Datei ganz ohne Kopfzeile, also nur mit Leerzeilen, ergibt `.malformed(line: 1)`.

### D7 Concurrency

- Beide Formate sind zustandslose `Sendable`-Werttypen. Ihre Leser sind lokale Werttypen in `read`.
- `CancellationCheck.tick()` läuft je Zeile und wirft `CancellationError`.
- Es gibt keinen gemeinsamen veränderlichen Zustand und keine Timeouts, weil ohne I/O gelesen wird.

### D8 Fixtures und Tests

- **Synthetische Fixtures in `Tests/GPSLoggerKitTests/Fixtures/` mit erfundenen Koordinaten um 50° N, 8° O:**
  - `v900-simple.csv`: NUL-gefüllte Felder, CRLF, Markierungen `C` und `V`, eine Zeile über Mitternacht.
  - `v900-pro.csv`: professioneller Modus mit den Breiten aus D1.
  - `iblue747.csv` und `iblue757.csv`: erzeugt mit gpsbabel aus `iblue-source.gpx`, ebenfalls unter `Fixtures/`.
- **Tests:** Kleine Texte im Test decken die Spec-Szenarien ab, ein Fixture-Test liest alle vier Dateien über `FileFormats.detect` und `FileFormats.read`. Die geschriebene GPX-Datei wird gegen das GPX-1.1-Schema geprüft.
- **Black-Box-Gegenprüfung:** einmalig von Hand mit dem gpsbabel-Binary (`-i v900` bzw. `-i iblue747`/`-i iblue757`, `-o gpx`). Das Ergebnis wird in `PROVENANCE.md` notiert, wie bei KML. Ein automatischer Test ist nicht möglich, weil das Binary Rosetta braucht und im Testziel nicht liegt.

## Risks / Trade-offs

- **Echte Dateien weichen ab:** Andere Spaltennamen, zusätzliche Kopfzeilen oder Einheiten in Klammern (etwa `HEIGHT(m)`) sind nicht beobachtet. → Die Spalten werden über den Namen gesucht, was robuster ist als feste Positionen. Der Hardware-Test (Task 6.2) prüft echte Dateien, Abweichungen führen zu einem Folge-Change.
- **Ortszeit statt UTC:** Liest der Hardware-Test Ortszeit, sind alle Zeiten um die Zeitzone verschoben. → Das ist im Proposal unter „Nicht im Umfang“ festgehalten und würde in einem eigenen Change mit Option nachgezogen.
- **`MM/TT/JJJJ`:** Eine amerikanische PC-Software könnte so schreiben, dann würden Tag und Monat vertauscht. → Diese Form ist nicht beobachtet. Erkennbar ist sie nur bei Tagen über 12, deshalb wird sie nicht geraten.
- **Endung `.csv`:** Beide Formate teilen sie, außerdem jede andere CSV-Datei. → Die Erkennung prüft die Kopfzeile, und fremde CSV-Dateien bleiben „unbekannt“.

## Migration Plan

Entfällt. Es gibt neue Formate, aber keine geänderten Schnittstellen. Rückbau: die beiden Einträge aus `FileFormats.all` entfernen.
