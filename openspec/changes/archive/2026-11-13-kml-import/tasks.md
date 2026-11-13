# Tasks: kml-import

## 1. Gemeinsame Bausteine

- [x] 1.1 `ImportWarningKind.missingTimes` mit `isPerFile == true` und Meldung nur mit Dateinamen anlegen (design.md D6), dazu die Lokalisierung (de, en). Prüfen: Ein Test prüft die Meldung auf Deutsch und Englisch, der Lokalisierungstest ist grün.
- [x] 1.2 `FileFormatID.kml` anlegen und `KMLFileFormat` (zunächst ohne Leselogik) mit dem Namen `format.kml` (de, en) und den Endungen `kml` und `kmz` in `FileFormats.all` eintragen. Prüfen: Der Katalogtest findet alle sieben Kennungen samt Endungen (Spec `logger-kit`, Szenario „Katalog abfragen“).

## 2. KMZ-Archive

- [x] 2.1 CRC-32 nach D1 (Polynom 0xEDB88320, Tabelle). Prüfen: `"123456789"` ergibt 0xCBF43926.
- [x] 2.2 Test-Encoder `KMZTestFile` im Testziel (D8): lokale Köpfe, Central Directory, End of Central Directory, „stored“ und „deflate“ (über `compression_encode_buffer`), optional Datendeskriptor (Bit 3), falsche CRC, Verschlüsselungs-Bit, ZIP64-Kennwerte, unbekanntes Packverfahren und übergroße Größenangabe. Prüfen: Ein mit dem Encoder geschriebenes Archiv lässt sich mit `/usr/bin/unzip -t` fehlerfrei testen (nur macOS).
- [x] 2.3 `KMZArchive` nach D3: End of Central Directory suchen, Central Directory lesen, Dokument wählen, Daten finden, mit `compression_stream` in 64-KiB-Blöcken entpacken, Abbruch nach jedem Block, Größendeckel 1 GiB, CRC-Prüfung mit Warnung.
- [x] 2.4 Tests zu 2.3. Prüfen:
  - Die Szenarien „Archiv mit Bildern“, „Anderer Dateiname“, „Falsche Prüfsumme“, „Kein KML im Archiv“ und „Abgeschnittenes Archiv“ der Spec `kml-import` sind abgedeckt.
  - Ein Archiv mit `doc.kml` in einem Unterordner und `tour.kml` im Wurzelverzeichnis liefert `tour.kml`.
  - Datendeskriptor, „stored“ und „deflate“ werden gelesen.
  - Verschlüsselung, ZIP64, ein unbekanntes Packverfahren und eine Größenangabe über 1 GiB enden mit einem Fehler, der die Datei nennt.
  - Ein Archiv, dessen Deflate-Strom mehr liefert als angegeben, endet mit einem Fehler.
  - Der Abbruch beim Entpacken eines Archivs mit über 50 MB endet in weniger als einer Sekunde mit `CancellationError`.

## 3. KML-Leser

- [x] 3.1 `KMLParserHandler` nach D4: Elemente am lokalen Namen erkennen, Baum aus Containern und Placemarks aufbauen, `name`, `description` und `TimeStamp/when` nur als direkte Kinder werten, `LineString`, `MultiGeometry`, `gx:Track`, `gx:MultiTrack` und `Point` mit ihrem `altitudeMode` sammeln, alles andere übergehen, Abbruch pro Element.
- [x] 3.2 Koordinaten lesen nach D4: `coordinates` mit Toleranz für Leerraum nach Kommas, `gx:coord`, Paarung mit `when`, Höhenregel je Geometrie, Warnungen `malformedRecord`, `invalidCoordinate` und `missingDate` mit Zeilennummer.
- [x] 3.3 Auswertung nach D4: Tracks und Segmente in Dateireihenfolge, Wegpunkte, Namensregel mit „Path“ und Rückfall auf Ordner, Dokument und Dateiname, Warnung `missingTimes` einmal pro Datei.
- [x] 3.4 Regel für den Punktordner von gpsbabel nach D5.
- [x] 3.5 `KMLFileFormat.read` und `matches` nach D2: ZIP-Signatur prüfen, gegebenenfalls über `KMZArchive` entpacken, dann parsen. Erkennung über `XMLSniffer` bzw. den ersten ZIP-Eintrag. Mehrere Dateien ergeben eine Aufzeichnung in der Reihenfolge der Übergabe.
- [x] 3.6 Tests zu 3.1 bis 3.5 mit kleinen KML-Texten im Test. Prüfen:
  - Die Szenarien der Spec `kml-import` sind abgedeckt:
    - „Einfacher Pfad“, „Pfad aus mehreren Teilen“, „Google-Mehrfachtrack“;
    - „Track mit Zeiten“, „Zu wenige Zeiten“;
    - „Markierung mit Beschreibung“, „Zeitgestempelte Punkte“;
    - „Track aus gpsbabel“, „Pfad ohne Namen“;
    - „Reihenfolge Länge, Breite“, „Ungültige Breite“;
    - „Export ohne Höhenbezug“, „Am Boden“, „Nur Nullen“;
    - „Standardausgabe von gpsbabel“, „Punkte passen nicht“;
    - „Export aus myTracks“;
    - „Gebietsgrenze“, „Netzwerk-Link“;
    - „Alte Google-Earth-Datei“;
    - „Abgeschnittene Datei“;
    - „KML mit Endung .xml“, „Anderes ZIP-Archiv“.
  - Ein `name` in `Style` oder `ExtendedData` wird nicht zum Tracknamen.
  - `gx:altitudeMode` `relativeToSeaFloor` verwirft die Höhe.
  - Ein Punktordner mit einer Abweichung von 0,00001° bleibt ein gewöhnlicher Ordner.
  - Eine Datei ohne Namensraum und eine mit nicht deklariertem `gx`-Präfix werden gelesen, wenn `XMLParser` sie annimmt; sonst ist das Verhalten als Fehler mit Zeile dokumentiert.
  - Der Abbruch einer KML-Datei mit über 50 MB endet in weniger als einer Sekunde mit `CancellationError`.

## 4. Fixtures und Dokumentation

- [x] 4.1 Die KML-Fixtures `mytracks.kml`, `gpsbabel.kml`, `gxtrack.kml` und `earth21.kml` nach D8 schreiben, mit erfundenen Koordinaten. Die Fixture `tour.kmz` (gepackte `doc.kml` und ein Bild) mit dem Test-Encoder erzeugen und unter `Fixtures/` ablegen. Prüfen: `gpsbabel.kml` und `gxtrack.kml` sind mit `xmllint` gültig nach `ogckml22.xsd` und `kml22gx.xsd`. `mytracks.kml` verwendet wie der echte myTracks-Export den Namensraum `http://earth.google.com/kml/2.2`, für den es kein Schema gibt. Sie ist, wie `earth21.kml`, mit dem Namensraum von KML 2.2 gültig. Ein Test stellt sicher, dass `tour.kmz` der Encoder-Ausgabe entspricht.
- [x] 4.2 Tests zu 4.1. Prüfen: Ein Test liest alle fünf Fixtures über `FileFormats.detect` und `FileFormats.read` und vergleicht Tracks, Segmente, Punktanzahl, erste und letzte Position, Zeiten, Höhen und Wegpunkte. Die daraus geschriebene GPX-Datei ist unter macOS gültig nach dem GPX-1.1-Schema.
- [x] 4.3 Black-Box-Gegenprüfung: Die GPX-Ausgabe von `gpsbabel.kml` mit der von gpsbabel 1.7.0 (`-i kml -f gpsbabel.kml -o gpx`) vergleichen. Prüfen: Punktanzahl, Positionen, Zeiten und Höhen stimmen überein. Abweichungen bei Wegpunkten und Namen werden in `PROVENANCE.md` notiert.
- [x] 4.4 `PROVENANCE.md` um den Abschnitt `kml` ergänzen (D1, mit der Beobachtung von gpsbabel vom 2026-11-04), dazu die Formattabelle im README des Pakets und die Formatliste im README des Repositorys. In `openspec/config.yaml` KML/KMZ in den nativen Umfang und in die Reihenfolge aufnehmen. Prüfen: Der Provenance-Test ist grün.

## 5. Abschluss

- [x] 5.1 `swift test` im Paket und alle Tests auf dem iOS-27.1-Simulator ausführen. Das Paket wie bisher in den Scratchpad kopieren und dort testen. Dazu `swift test` für GPSLoaderKit und `xcodebuild test` für die App. Prüfen: alles grün. Die App zeigt im Bereich „Dateien“ das neue Format (Snapshot).
- [x] 5.2 `openspec validate kml-import --strict` ausführen. Prüfen: gültig.
- [ ] 5.3 [manuell, Hardware] Der Entwickler konvertiert in der App die KML- und KMZ-Dateien, die er hat, etwa Exporte aus myTracks, Google Earth oder Logger-Programmen. Prüfen:
  - Tracks, Punktanzahl und Höhen sind plausibel und stimmen mit gpsbabel 1.7.0 (`-i kml`, Black-Box) überein.
  - Dateien, bei denen zeitgestempelte Punkte als Wegpunkte statt als Track erscheinen, werden als Kandidaten für Stufe B notiert.
  - KMZ-Dateien, die nicht erkannt werden, werden ebenfalls notiert.
