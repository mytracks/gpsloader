# kml-import Specification

## Purpose
Liest KML-Dateien (Keyhole Markup Language) und KMZ-Archive ein, wie sie Google Earth, Tracker-Apps, gpsbabel und myTracks schreiben. Aus Pfaden und Google-Tracks entstehen Tracks, aus Punkten Wegpunkte, ohne gpsbabel.

## Requirements

### Requirement: Tracks aus Pfaden
Jedes `Placemark`, das mindestens eine `LineString` oder einen `gx:Track` enthält, SHALL genau einen Track ergeben. Jede `LineString` und jeder `gx:Track` darin SHALL ein eigenes Segment ergeben, in der Reihenfolge der Datei, auch innerhalb von `MultiGeometry` und `gx:MultiTrack`. Die Punkte einer `LineString` SHALL ohne Zeit übernommen werden. Segmente ohne Punkte SHALL entfallen.

#### Scenario: Einfacher Pfad
- **WHEN** ein `Placemark` eine `LineString` mit 100 Koordinaten enthält
- **THEN** entsteht ein Track mit einem Segment aus 100 Punkten ohne Zeit

#### Scenario: Pfad aus mehreren Teilen
- **WHEN** ein `Placemark` eine `MultiGeometry` mit zwei `LineString` zu je 3 Koordinaten enthält
- **THEN** entsteht ein Track mit zwei Segmenten zu je 3 Punkten

#### Scenario: Google-Mehrfachtrack
- **WHEN** ein `Placemark` einen `gx:MultiTrack` mit zwei `gx:Track` enthält
- **THEN** entsteht ein Track mit zwei Segmenten

### Requirement: Google-Tracks
Ein `gx:Track` SHALL seine Punkte aus den `gx:coord`-Elementen bilden (Länge, Breite und optional Höhe, durch Leerzeichen getrennt). Das n-te `when` SHALL die Zeit des n-ten Punkts sein. Gibt es weniger `when` als `gx:coord`, SHALL der Rest ohne Zeit übernommen und als Warnung gezählt werden. Überzählige `when` SHALL ignoriert werden. Eine nicht lesbare Zeit SHALL wie eine fehlende zählen.

#### Scenario: Track mit Zeiten
- **WHEN** ein `gx:Track` die Zeiten `2026-05-01T08:00:00Z` und `2026-05-01T08:00:10Z` sowie die Koordinaten `8 50 120` und `8.001 50.001 121` enthält
- **THEN** entstehen zwei Punkte mit Breite 50 bzw. 50,001, Länge 8 bzw. 8,001, den Höhen 120 m und 121 m und diesen Zeiten

#### Scenario: Zu wenige Zeiten
- **WHEN** ein `gx:Track` 3 `gx:coord`, aber nur 2 `when` enthält
- **THEN** hat der dritte Punkt keine Zeit, und eine Warnung zählt einen Punkt ohne Datum

### Requirement: Wegpunkte
Jedes `Point` in einem `Placemark` SHALL einen Wegpunkt ergeben, auch wenn das `Placemark` eine Zeit trägt. Der Wegpunkt SHALL `name` als Namen, `description` als Kommentar und die Zeit aus `TimeStamp/when` bekommen, soweit vorhanden. Eine nicht lesbare Zeit eines Wegpunkts SHALL ohne Warnung entfallen. Ausgenommen sind die Punkte des Ordners „Points“ nach der Anforderung „Zeiten aus dem Punktordner von gpsbabel“.

#### Scenario: Markierung mit Beschreibung
- **WHEN** ein `Placemark` „Hütte“ mit der Beschreibung „Rast“ und einem `Point` vorkommt
- **THEN** entsteht ein Wegpunkt „Hütte“ mit dem Kommentar „Rast“

#### Scenario: Zeitgestempelte Punkte
- **WHEN** ein Ordner „Fotos“ 5 `Placemark` mit `Point` und `TimeStamp` enthält
- **THEN** entstehen 5 Wegpunkte mit diesen Zeiten und kein Track

### Requirement: Namen der Tracks
Ein Track SHALL den `name` seines `Placemark` bekommen. Fehlt dieser, ist er leer oder lautet er „Path“ (der feste Platzhalter von gpsbabel), SHALL der Track den Namen des nächsten umgebenden `Folder` oder `Document` mit Namen bekommen, sonst den Dateinamen ohne Endung.

#### Scenario: Track aus gpsbabel
- **WHEN** ein `Placemark` „Path“ in einem `Folder` „Morgenrunde“ liegt
- **THEN** heißt der Track „Morgenrunde“

#### Scenario: Pfad ohne Namen
- **WHEN** die Datei `tour.kml` ein `Placemark` ohne `name` direkt unter einem `Document` ohne `name` enthält
- **THEN** heißt der Track „tour“

### Requirement: Koordinaten
Ein `coordinates`-Element SHALL Tupel aus Länge, Breite und optional Höhe enthalten, durch Kommas getrennt. Die Tupel sind durch Leerraum getrennt, und Leerraum nach einem Komma SHALL toleriert werden. Ein Tupel mit weniger als zwei lesbaren Zahlen MUST verworfen und als Warnung gezählt werden. Ebenso eine Position außerhalb des gültigen Bereichs.

#### Scenario: Reihenfolge Länge, Breite
- **WHEN** eine `LineString` das Tupel `8.5,50.25,100` enthält
- **THEN** hat der Punkt die Breite 50,25 und die Länge 8,5

#### Scenario: Ungültige Breite
- **WHEN** ein Tupel die Breite 95 hat
- **THEN** wird es verworfen, und eine Warnung zählt es

### Requirement: Höhe
Die Höhe einer `LineString`, eines `Point` oder eines `gx:Track` SHALL übernommen werden, wenn deren `altitudeMode` bzw. `gx:altitudeMode` `absolute` lautet oder fehlt. Bei ausdrücklich gesetztem `clampToGround`, `relativeToGround`, `clampToSeaFloor` oder `relativeToSeaFloor` SHALL die Höhe leer bleiben, ebenso wenn alle Höhen dieser Geometrie 0 sind.

#### Scenario: Export ohne Höhenbezug
- **WHEN** eine `LineString` ohne `altitudeMode` die Höhen 100, 101 und 102 enthält
- **THEN** haben die Punkte diese Höhen

#### Scenario: Am Boden
- **WHEN** eine `LineString` mit `altitudeMode` `clampToGround` die Höhe 100 enthält
- **THEN** haben die Punkte keine Höhe

#### Scenario: Nur Nullen
- **WHEN** alle Tupel einer `LineString` die Höhe 0 haben
- **THEN** haben die Punkte keine Höhe

### Requirement: Zeiten aus dem Punktordner von gpsbabel
Ein `Folder` „Points“ SHALL dem Track seines Nachbar-Placemarks die Zeiten liefern, wenn:
- er im selben Container genau ein `Placemark` mit Pfaden hat;
- jedes `Placemark` in ihm einen `Point` mit lesbarer Zeit hat;
- Anzahl und Koordinaten, auf 0,000001° genau, mit allen Punkten dieses Tracks übereinstimmen.

Seine Punkte SHALL dann keine Wegpunkte ergeben. Sonst SHALL er wie jeder andere Ordner gelesen werden.

#### Scenario: Standardausgabe von gpsbabel
- **WHEN** ein `Folder` „Lauf“ ein `Placemark` „Path“ mit einer `MultiGeometry` aus zwei `LineString` zu je 3 Punkten und einen `Folder` „Points“ mit 6 passenden zeitgestempelten Punkten enthält
- **THEN** entsteht ein Track „Lauf“ mit zwei Segmenten zu je 3 Punkten mit diesen Zeiten und kein Wegpunkt

#### Scenario: Punkte passen nicht
- **WHEN** der `Folder` „Points“ 5 Punkte enthält, der Track aber 6
- **THEN** bleibt der Track ohne Zeiten, und die 5 Punkte werden Wegpunkte

### Requirement: Tracks ohne Zeiten
Enthält eine Datei mindestens einen Track, dessen Punkte alle keine Zeit haben, SHALL eine einzige Warnung je Datei darauf hinweisen. Für diese Punkte SHALL es keine Warnung „ohne Datum“ geben.

#### Scenario: Export aus myTracks
- **WHEN** eine Datei einen Pfad mit 500 Koordinaten ohne Zeiten enthält
- **THEN** entsteht ein Track mit 500 Punkten, und genau eine Warnung nennt die Datei als ohne Zeitangaben

### Requirement: Unbekannte Inhalte
Der Import SHALL `Polygon`, `LinearRing`, `Model`, Overlays, Styles, `ExtendedData`, `TimeSpan`, Kamera-Elemente, `gx:Tour` und unbekannte Elemente ohne Warnung übergehen. `NetworkLink` SHALL nicht abgerufen werden. Ordner und Dokumente SHALL in jeder Tiefe gelesen werden.

#### Scenario: Gebietsgrenze
- **WHEN** eine Datei neben einem Pfad ein `Placemark` mit `Polygon` enthält
- **THEN** entsteht nur der Track des Pfads, ohne Warnung

#### Scenario: Netzwerk-Link
- **WHEN** eine Datei nur einen `NetworkLink` enthält
- **THEN** wird keine Verbindung aufgebaut, und das Einlesen meldet „keine verwertbaren Daten“

### Requirement: Namensräume
Der Import SHALL Dateien mit dem Namensraum von KML 2.2 (`http://www.opengis.net/kml/2.2`), mit den Google-Namensräumen `http://earth.google.com/kml/2.0`, `2.1` und `2.2` und ohne Namensraum gleich behandeln. Die Elemente von Googles Erweiterung SHALL an ihrem Namen erkannt werden, mit oder ohne Präfix.

#### Scenario: Alte Google-Earth-Datei
- **WHEN** eine Datei den Namensraum `http://earth.google.com/kml/2.1` verwendet
- **THEN** entstehen dieselben Tracks und Wegpunkte wie bei KML 2.2

### Requirement: KMZ-Archive
Ein KMZ-Archiv SHALL als ZIP-Archiv gelesen werden. Gelesen wird das Dokument `doc.kml` im Wurzelverzeichnis, sonst die erste Datei mit Endung `.kml` im Wurzelverzeichnis. Die Einträge können ungepackt („stored“) oder mit „deflate“ gepackt sein. Alle anderen Einträge SHALL ignoriert werden. Für das Dokument gelten dieselben Regeln wie für eine KML-Datei.

#### Scenario: Archiv mit Bildern
- **WHEN** ein KMZ-Archiv eine gepackte `doc.kml` mit einem Pfad und zwei Bilder enthält
- **THEN** entsteht der Track des Pfads

#### Scenario: Anderer Dateiname
- **WHEN** ein KMZ-Archiv nur `tour.kml` und keine `doc.kml` enthält
- **THEN** wird `tour.kml` gelesen

### Requirement: Beschädigte KMZ-Archive
Eine falsche Prüfsumme (CRC-32) des gelesenen Dokuments SHALL eine Warnung ergeben, die die Datei nennt. Das Dokument SHALL trotzdem gelesen werden. Ein Archiv ohne KML-Dokument oder ein abgeschnittenes Archiv MUST zu einem Fehler mit der Datei führen. Ebenso ein verschlüsseltes Dokument, ein unbekanntes Packverfahren, ZIP64 oder ein Dokument, das entpackt größer als 1 GiB wäre.

#### Scenario: Falsche Prüfsumme
- **WHEN** die CRC-32 der `doc.kml` nicht zum Inhalt passt
- **THEN** enthält die Aufzeichnung den Inhalt des Dokuments, und eine Warnung nennt die Datei

#### Scenario: Kein KML im Archiv
- **WHEN** ein ZIP-Archiv, das nur Bilder enthält, als KMZ gelesen wird
- **THEN** endet das Einlesen mit einem Fehler, der die Datei nennt

#### Scenario: Abgeschnittenes Archiv
- **WHEN** ein KMZ-Archiv nach der Hälfte endet
- **THEN** endet das Einlesen mit einem Fehler, der die Datei nennt

### Requirement: Fehler
Ein KML-Dokument, das kein wohlgeformtes XML ist, MUST zu einem Fehler mit Datei und Zeile führen.

#### Scenario: Abgeschnittene Datei
- **WHEN** eine KML-Datei mitten in einem `coordinates`-Element endet
- **THEN** endet das Einlesen mit einem Fehler, der Datei und Zeile nennt

### Requirement: Erkennung
Eine Datei SHALL als KML erkannt werden, wenn ihr erstes Element `kml` ist, mit oder ohne Namensraum-Präfix. Ein ZIP-Archiv SHALL als KML erkannt werden, wenn sein erster Eintrag eine Datei mit Endung `.kml` ist. Die Endungen `.kml` und `.kmz` SHALL nur als Hinweis dienen.

#### Scenario: KML mit Endung .xml
- **WHEN** eine KML-Datei die Endung `.xml` hat
- **THEN** schlägt die Erkennung KML vor

#### Scenario: Anderes ZIP-Archiv
- **WHEN** ein Word-Dokument (`.docx`, ein ZIP-Archiv) geprüft wird
- **THEN** wird es nicht als KML erkannt
