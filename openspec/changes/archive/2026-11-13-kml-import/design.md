# Design: KML- und KMZ-Import

## Context

GPSLoggerKit hat den Formatvertrag `FileFormat` (`matches(prefix:)` auf die ersten 4096 Byte, `read(_:)`), den `WarningCollector`, `CancellationCheck` und `XMLSniffer.rootElementLocalName(in:)`. Die XML-Formate GPX, TCX und Suunto lesen mit `XMLParser` und einem eigenen Delegate (`shouldProcessNamespaces`, externe Entitäten aus, Abbruch über `abortParsing`). Mit FIT gibt es die Warnungen pro Datei (`ImportWarningKind.isPerFile`) und einen Binärleser, der ohne Kopien über `withUnsafeBytes` arbeitet. Das Datenmodell erlaubt Punkte ohne Zeit und ohne Höhe, Wegpunkte haben Name, Kommentar und Zeit.

So arbeitete die Alt-App:
- **Lesen:** über gpsbabel, `GPSBabel.convertKML:toGPX:` in `input/mytracks4mac/DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`, Zeilen 654–666 (`-i kml -f … -o gpx`).
- **Schreiben, eigener Code:**
  - `Track.createKMLTrackForParent:` in `DsTrackFramework/Source/Classes/Track.m`, ab Zeile 612: `Placemark` mit `name`, darin eine `LineString` mit `lon,lat,alt` je Zeile und ohne `altitudeMode`.
  - `TrackPoint.createKMLPlacemarkForParent:` in `DsTrackFramework/Source/Classes/TrackPoint.m`, ab Zeile 702: Wegpunkte als `Placemark`/`Point`.
  - KMZ entstand über `zip` in `ImportExport/TrackKML.m`, Zeile 215.

## Goals / Non-Goals

**Goals:**
- KML und KMZ auf macOS und iOS ohne gpsbabel und ohne Fremdbibliothek. Erkennung, Warnungen und Abbruch funktionieren wie bei den übrigen Formaten.
- Exporte von myTracks und die Standardausgabe von gpsbabel 1.7.0 ergeben dieselben Punkte, Zeiten und Höhen wie die Ausgangsdaten.

**Non-Goals:**
- Ein vollständiges KML-Objektmodell. Ausgewertet werden nur die Elemente aus D4. Styles, Vererbung von Styles und `Update`-Elemente werden ignoriert.
- Ein allgemeiner ZIP-Leser. Der Leser kennt nur das, was KMZ braucht (D3), und bleibt intern.

## Decisions

### D1 Quellen und Clean-Room

- **KML:**
  - OGC KML 2.2 (OGC 07-147r2) mit dem Schema `ogckml22.xsd`.
  - Googles „KML Extensions“-Referenz (`gx:Track`, `gx:MultiTrack`, `gx:coord`, `gx:altitudeMode`) mit dem Schema `kml22gx.xsd`.
  - Für die alten Namensräume `http://earth.google.com/kml/2.0`, `2.1` und `2.2` gilt die KML-Referenz von Google. Die Elemente, die hier ausgewertet werden, haben dort dieselben Namen.
- **ZIP:** die öffentliche Spezifikation `APPNOTE.TXT` von PKWARE: lokaler Eintragskopf, Central Directory, End of Central Directory, Packverfahren 0 und 8, Bit 0 (verschlüsselt) und Bit 3 (Datendeskriptor). Deflate (RFC 1951) dekodiert Apples `Compression`-Framework.
- **CRC-32:** das öffentlich dokumentierte Polynom 0xEDB88320 (ISO 3309), umgesetzt mit Tabelle. Prüfwert für `"123456789"`: 0xCBF43926.
- **Eigener Code:** der myTracks-Export, siehe Context.
- **Black-Box:**
  - Am 2026-11-04 wurde das gpsbabel-1.7.0-Binary mit einer GPX-Datei aus synthetischen Fixtures ausgeführt, mit `-o kml`, `-o kml,points=0` und `-o kml,trackdata=0,points=0`. Den Quelltext von gpsbabel liest niemand.
  - Beobachtet wurde:
    - `Document` mit `name` „GPS device“.
    - `Folder` „Waypoints“ mit `Placemark`/`TimeStamp`/`Point`.
    - `Folder` „Tracks“, darin je Track ein `Folder` mit dem Tracknamen.
    - In diesem Track-Ordner liegt ein `Placemark` „Path“ mit einer `LineString` (`tessellate` 1) oder, bei mehreren Segmenten, einer `MultiGeometry` mit einer `LineString` je Segment.
    - In der Standardausgabe liegt daneben ein `Folder` „Points“ mit einem `Placemark` je Trackpunkt (Name `<Track>-<n>`, `TimeStamp`, `Point`), in derselben Reihenfolge und über alle Segmente fortlaufend.
    - Koordinaten werden mit 6 Nachkommastellen geschrieben, Höhen mit 2. Ein `altitudeMode` fehlt überall.
- `PROVENANCE.md` bekommt den Abschnitt `kml`. Der vorhandene Provenance-Test verlangt das für jedes Format im Katalog.

### D2 Ein Format für KML und KMZ

`KMLFileFormat` (Kennung `kml`, Endungen `kml`, `kmz`) erkennt beides in `matches(prefix:)`:
- **XML:** `XMLSniffer.rootElementLocalName(in:) == "kml"`.
- **ZIP:** Byte 0–3 sind `50 4B 03 04`. Der Name des ersten Eintrags, dessen Länge in Byte 26–27 steht und der ab Byte 30 beginnt, endet ohne Rücksicht auf Groß- und Kleinschreibung auf `.kml`.

`read` prüft zuerst die ZIP-Signatur, entpackt dann (D3) und liest danach das Dokument (D4).

- **Alternative:** zwei Formate `kml` und `kmz`. Verworfen, weil es für Anwender dasselbe Format ist und die App ohnehin nach Inhalt erkennt. Die Mehrfach-Datei-Regel gilt so auch für eine gemischte Auswahl aus KML- und KMZ-Dateien.
- **Alternative:** jedes ZIP-Archiv als KMZ erkennen. Verworfen, weil `.docx`, `.xlsx` oder `.epub` dann als KML vorgeschlagen würden und erst beim Lesen scheiterten.

### D3 ZIP-Leser

Interner Werttyp `KMZArchive` in `Formats/KML/KMZArchive.swift`, Ablauf:

1. **Ende suchen:** Das End-of-Central-Directory (`50 4B 05 06`) wird rückwärts in den letzten 65 557 Byte gesucht. Fehlt es, endet das Lesen mit `GPSLoggerError(.malformed(line: nil))` und dem Detail „truncated or invalid ZIP archive“.
2. **Einträge lesen:** Das Central Directory wird gelesen. Folgende Fälle führen zu `GPSLoggerError(.unreadable)` mit Detail:
   - ein ZIP64-Kennwert (`0xFFFF`/`0xFFFFFFFF`) oder ein ZIP64-Locator;
   - Bit 0 (verschlüsselt) beim gewählten Eintrag;
   - ein anderes Packverfahren als 0 oder 8.
3. **Dokument wählen:** Gewählt wird `doc.kml` im Wurzelverzeichnis, sonst der erste Eintrag ohne `/` im Namen, der auf `.kml` endet. Fehlt beides, endet das Lesen mit `GPSLoggerError(.noUsableData)` und dem Detail „no KML document in archive“.
4. **Daten finden:** Die Daten beginnen nach dem lokalen Kopf, dessen Namens- und Extra-Länge aus dem lokalen Kopf selbst stammen. Größen und CRC kommen aus dem Central Directory, damit Einträge mit Datendeskriptor (Bit 3) funktionieren. Reichen die Daten über das Dateiende hinaus, ist das Archiv abgeschnitten (Fehler wie in Schritt 1).
5. **Entpacken:** mit `compression_stream` und `COMPRESSION_ZLIB` (Raw-Deflate), in Blöcken zu 64 KiB:
   - Nach jedem Block prüft `Task.checkCancellation()`.
   - Eine angegebene entpackte Größe über 1 GiB wird vor dem Entpacken abgelehnt. Wächst die Ausgabe über die angegebene Größe hinaus, wird abgebrochen (`.malformed`).
   - Endet der Deflate-Strom vorzeitig, ist das Archiv abgeschnitten.
6. **Prüfsumme:** Stimmt die CRC-32 nicht, gibt es die Warnung `fileChecksumMismatch`. Das Dokument wird trotzdem gelesen.

- **Alternative:** ZIPFoundation (MIT). Verworfen, weil das Paket ohne Abhängigkeiten bleiben soll und der benötigte Teil klein ist.
- **Alternative:** `NSFileCoordinator` mit `.forUploading` oder `Archive` aus `AppleArchive`. Verworfen: Das eine packt nur, das andere liest kein ZIP.

### D4 KML-Leser

`KMLParserHandler` (intern) mit `shouldProcessNamespaces = true`. Elemente werden nur am lokalen Namen erkannt, deshalb sind alle Namensräume und Präfixe gleichwertig. KML 2.2 hat keine eigenen Elemente namens `Track`, `MultiTrack` oder `coord`, sie stammen nur aus `gx`. Ein Element-Stapel liefert den Kontext.

Beim Lesen entsteht ein kleiner Baum, ohne XML-Knoten:
- **Container** (`Document`, `Folder`, `kml`): eigener `name` und Kinder in Dateireihenfolge.
- **Placemark:**
  - eigener `name`, `description` und `TimeStamp/when`;
  - Geometrien: `LineString`- und `gx:Track`-Segmente sowie `Point`, jeweils mit ihrem `altitudeMode` bzw. `gx:altitudeMode` als direktem Kind.

`name`, `description` und `when` zählen nur als direkte Kinder ihres Elements bzw. von `TimeStamp`. Ein `name` in `Style`, `Schema` oder `ExtendedData` zählt also nicht. Text wird nur in Elementen gesammelt, die ausgewertet werden.

Die Auswertung nach dem Parsen:
1. **Punktordner von gpsbabel:** Die Regel aus D5 läuft je Container.
2. **Tracks und Wegpunkte:** Der Baum wird in Tiefe zuerst und in Dateireihenfolge durchlaufen. Placemarks mit Pfaden werden Tracks. Jeder `Point` wird ein Wegpunkt mit dem `name` und der `description` seines Placemark.
3. **Namen:** nach der Spec-Regel. „Path“ wird exakt verglichen, nach Entfernen von Leerraum am Rand.
4. **Warnung pro Datei:** Ist ein Track ganz ohne Zeiten übrig, gibt es einmal `missingTimes` (D6).

Koordinaten werden so gelesen:
- **`coordinates`:** Leerraum direkt nach einem Komma wird entfernt, dann wird an Leerraum getrennt und jedes Tupel an Kommas.
- **`gx:coord`:** an Leerraum getrennt, 2 oder 3 Zahlen.
- Zahlen liest `Double(Substring)`, das unabhängig von der Locale ist.
- Höhenregel je Geometrie: Bei ausdrücklichem Bodenbezug wird keine Höhe gesetzt. Sonst wird keine Höhe gesetzt, wenn alle Höhen 0 sind oder fehlen.
- Zeiten liest `ISO8601.date`. Werte ohne Zeitzone gelten als UTC, so wie bei GPX und TCX.

Warnungen tragen die Zeilennummer des Parsers am Ende des `coordinates`- bzw. `gx:Track`-Elements:
- `malformedRecord` für ein nicht lesbares Tupel;
- `invalidCoordinate` für eine Position außerhalb des gültigen Bereichs;
- `missingDate` für einen `gx:coord` ohne passendes `when`.

- **Alternative:** Elemente nur in bekannten Namensräumen akzeptieren. Verworfen, weil Dateien ohne Namensraum und mit falsch deklariertem `gx`-Präfix in der Praxis vorkommen. Die lokalen Namen sind auch so eindeutig.

### D5 Regel für den Punktordner von gpsbabel

Für einen Container C mit einem direkten Kind-`Folder` P und dem `name` „Points“:
1. C hat genau ein direktes Kind-Placemark T mit `LineString`-Segmenten und ohne `gx:Track`.
2. P enthält nur Placemarks. Jedes hat genau einen `Point` und eine lesbare Zeit.
3. Die Zahl der Punkte in P gleicht der Gesamtzahl der gültigen Punkte von T über alle Segmente.
4. Paarweise weichen Breite und Länge höchstens um 0,000001° ab, plus 1e-9 für Rundung.

Treffen alle vier Bedingungen zu, bekommen die Punkte von T der Reihe nach die Zeiten aus P, und P wird aus dem Baum entfernt. Sonst bleibt P ein gewöhnlicher Ordner.

Die Toleranz deckt die 6 Nachkommastellen von gpsbabel ab. Weil beide Werte aus derselben Quelle stammen, sind sie in der Praxis identisch.

- **Alternative:** jeden Ordner mit zeitgestempelten Punkten als Track lesen, also Stufe B. Verworfen, weil dafür keine repräsentativen Dateien vorliegen (Entscheidung vom 2026-11-04).
- **Alternative:** den Ordner nur verwerfen. Verworfen, weil die Zeiten dann verloren gingen (Entscheidung vom 2026-11-04).

### D6 Warnungen

`ImportWarningKind` bekommt den Fall `missingTimes` mit `isPerFile == true`. Bei CRC-Fehlern im KMZ wird `fileChecksumMismatch` wiederverwendet.

Lokalisierung:

| Schlüssel | Deutsch | Englisch |
|---|---|---|
| `warning.missingTimes` | „„%@“ enthält Tracks ohne Zeitangaben.“ | „“%@” contains tracks without times.“ |
| `format.kml` | „KML/KMZ (Google Earth)“ | „KML/KMZ (Google Earth)“ |

Die genaue Wortwahl legt die Umsetzung fest.

### D7 Nebenläufigkeit und Abbruch

Wie bei den übrigen Formaten:
- `read` ist synchron und wird von `FileFormats.read` außerhalb des Main Actors aufgerufen.
- `KMLFileFormat` und `KMZArchive` sind `Sendable`-Werttypen. Der `compression_stream` und der Parser-Delegate leben nur innerhalb eines `read`-Aufrufs und verlassen ihn nicht.
- Abbruch wird an drei Stellen geprüft:
  - beim Entpacken nach jedem 64-KiB-Block;
  - beim Parsen über `CancellationCheck` pro Element;
  - bei der Auswertung pro Placemark.
- Nach einem Abbruch kommt `CancellationError` ohne Teilergebnis.
- Ein Zeitlimit ist nicht nötig, weil Dateien endlich sind und der Größendeckel aus D3 gilt.

### D8 Tests und Fixtures

- **KML-Fixtures**, von Hand geschrieben mit erfundenen Koordinaten um 50° N / 8° E:
  - `mytracks.kml`: Aufbau wie im myTracks-Export, mit zwei Wegpunkten und wie dort mit dem Namensraum `http://earth.google.com/kml/2.2` (`ImportExport/TrackKML.m`).
  - `gpsbabel.kml`: die Ausgabe des gpsbabel-1.7.0-Binaries (`-o kml`) für eine synthetische GPX-Datei mit zwei Segmenten und einem Wegpunkt, also echte Standardausgabe mit Ordner „Points“.
  - `gxtrack.kml`: `gx:MultiTrack` mit zwei `gx:Track`, `altitudeMode` `absolute`.
  - `earth21.kml`: alter Namensraum, `LineString` mit `clampToGround`.
- **Schemaprüfung:** `gpsbabel.kml` und `gxtrack.kml` werden einmalig mit `xmllint` gegen `ogckml22.xsd` und `kml22gx.xsd` geprüft. Für die Google-Namensräume von `mytracks.kml` und `earth21.kml` gibt es kein Schema. Sie werden mit eingesetztem Namensraum von KML 2.2 geprüft. Die XSDs bleiben im Scratchpad und kommen nicht ins Paket.
- **KMZ:** Ein Test-Encoder `KMZTestFile` im Testziel schreibt lokale Köpfe, Central Directory und das Ende des Archivs. Er kann ungepackt oder mit Deflate über `compression_encode_buffer` schreiben und optional Bit 3, eine falsche CRC, Verschlüsselungs-Bit, ZIP64-Kennwerte und eine übergroße Größenangabe setzen.
  - Daraus erzeugt ein Testlauf `tour.kmz`. Wie die FIT-Fixtures liegt sie als Binärdatei unter `Fixtures/`.
- **Abbruch:** eine KML-Datei mit über 50 MB und ein KMZ mit über 50 MB entpackt. Beide müssen in weniger als einer Sekunde mit `CancellationError` enden.
- **GPX-Ausgabe:** Für alle Fixtures wird die GPX-Ausgabe gegen das GPX-XSD validiert, wie bei den übrigen Formaten.

## Risks / Trade-offs

- [Die Regeln stützen sich nur auf Standard und zwei beobachtete Erzeuger; Dateien anderer Programme können anders aufgebaut sein] → Unbekannte Strukturen fallen auf die allgemeinen Regeln zurück. Im schlimmsten Fall entstehen Wegpunkte statt eines Tracks, Daten gehen nicht verloren. Die manuelle Prüfung mit beliebigen KML-Dateien des Entwicklers zeigt Lücken für einen späteren Change auf.
- [Ein KMZ, dessen erster Eintrag kein `.kml` ist, wird nicht erkannt] → Google Earth schreibt `doc.kml` zuerst. Andere Fälle erscheinen im Dateimodus als „nicht unterstützt“. Bei Bedarf kann die Erkennung später alle lokalen Köpfe im Dateianfang prüfen.
- [Die Regel „alle Höhen 0 bedeutet keine Höhe“ verwirft echte Höhen von 0 m, etwa an der Küste] → Das betrifft nur Geometrien, die durchgehend auf genau 0 m liegen. Das ist bei echten Messungen praktisch ausgeschlossen, bei Google-My-Maps-Exporten aber die Regel.
- [Ein Placemark, das wirklich „Path“ heißt, bekommt den Namen seines Ordners] → Das wird in Kauf genommen. Sonst hießen alle Tracks aus gpsbabel „Path“.
- [Sehr große `coordinates`-Texte belegen viel Speicher] → Jeder Text wird nur einmal als String gehalten und direkt nach dem Element ausgewertet. Die Punkte selbst brauchen ohnehin Speicher.
- [Ein bösartiges KMZ mit hohem Packfaktor] → Der Deckel von 1 GiB und der Vergleich mit der angegebenen Größe (D3) begrenzen den Speicher.

## Migration Plan

Keine. Ein neues Format und eine neue Warnungsart kommen dazu, vorhandene Kennungen und APIs bleiben unverändert.
