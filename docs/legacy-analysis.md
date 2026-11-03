# Analyse: GPS-Logger-Funktionalität in myTracks (Alt-App)

Dieses Dokument fasst zusammen, wie myTracks heute GPS-Logger ausliest. Es dient als
fachliche Referenz für die Neuimplementierung in gpsloader. Der Originalcode liegt unter
`input/mytracks4mac/`. Der Ordner ist per `.gitignore` nicht versioniert, deshalb sind hier
alle relevanten Details festgehalten. Pfade in diesem Dokument beziehen sich auf
`input/mytracks4mac/`.

Ergänzend: [legacy-device-catalog.md](legacy-device-catalog.md) enthält alle 143 Geräte-Einträge des
aktuellen Stands. Geräte, die in früheren Versionen entfernt wurden (i-GotU, Wintec WPL 1000), sind
hier in den Abschnitten 3.2 und 4 beschrieben.

Welche Teile gpsloader übernimmt, ist nicht hier festgelegt, sondern in `openspec/config.yaml`.
Dieses Dokument beschreibt nur das Verhalten der Alt-App.

Die Alt-App ist ein Git-Repository. Gelöschter Code lässt sich mit `git show <commit>^:<pfad>` abrufen.
Wichtige Commits:

| Commit | Datum | Inhalt |
|---|---|---|
| `b1ac5a3` | 2016-06-11 | initial checkin (die Historie beginnt hier) |
| `fdb8054` | 2025-02-04 | myTracks 4.4.0, gpsbabel 1.9.0 (universal) |
| `e0d1f18` | 2025-04-19 | „rollback of gpsbabel“: Rückkehr zu gpsbabel 1.7.0 (myTracks 4.4.3) |
| `3cbc727` | 2026-10-19 | myTracks 4.5.0: Intel-Support, i-GotU und WPL 1000 entfernt, gpsbabel 1.10.0 |

---

## 1. Überblick und Begriffe

myTracks kennt drei **GPS-Modi** (`GpsMode` in `DsUtilities/.../DsPreferences`):

| Modus | Bedeutung | Relevanz für gpsloader |
|---|---|---|
| `GpsModeDirect` | Gerät hängt seriell an (USB-Seriell-Adapter oder Bluetooth-SPP), wird aktiv ausgelesen | **Kern** |
| `GpsModeUsbStorage` | Gerät ist Massenspeicher oder SD-Karte; Dateien werden ausgewählt und konvertiert | **Kern** (Dateimodus) |
| `GpsModeLoadMyTracks` | Auslesen über die Fremd-App *LoadMyTracks* (ScriptingBridge, `com.ClueTrust.LoadMyTracks`) | **nicht übernehmen** |

Eine **Logger-Konfiguration** besteht aus:

- `device`: Name des seriellen Geräts **ohne** `/dev/cu.`-Präfix (z. B. `SLAB_USBtoUART`, `usbmodem1421`).
  Sonderwert `auto` bei Geräten, die keine Gerätewahl brauchen.
- `deviceType`: Treiber-String. Er codiert den Treibertyp (siehe Abschnitt 3).
- `additionalArguments`: Zusatzargumente für gpsbabel (siehe 3.1).
- `gpsFileFormat` und `gpsFileAdditionalArguments`: nur für den Dateimodus.

Mehrere benannte Konfigurationen werden in den UserDefaults gespeichert
(`myTracks/Source/Classes/NewControllers/LoggerConfiguration/LoggerConfigurations.swift`).
Schlüssel: `LoggerConfigurationsCount`, `LoggerConfigurationName<i>`,
`LoggerConfigurationDeviceType<i>`, `LoggerConfigurationDevice<i>`,
`LoggerConfigurationAdditionalArguments<i>`, `LoggerConfigurationGpsFileFormat<i>`,
`LoggerConfigurationGpsFileAdditionalArguments<i>` und `LoggerConfigurationGpsMode<i>`.
myTracks läuft in der Sandbox (`info.stichling.myTracks`), die Werte liegen also in dessen Container.
Für gpsloader ist **keine Übernahme** dieser Konfigurationen vorgesehen.

## 2. Ablauf „Daten vom Logger importieren“ (Direktmodus)

Quelle: `myTracks/Source/Classes/Controller/MyTracksMainController.m`
(`importFromGPSDevice:`, `importFromGPSDeviceThread`, `deleteDataFromGPSDevice:`).

1. Ein Hintergrund-Thread startet. Die UI zeigt ein nicht-modales Fortschrittspanel ohne echten Fortschritt.
2. `GPSBabel importTracksAndWaypointToFile:` schreibt eine temporäre GPX-Datei (`device.gpxx` in Application Support).
3. Die Gerätenamen werden korrigiert (`correctDeviceNameWithDynamicPrefix:`). Für die Präfixe
   `usbmodem` und `PL2303` gilt: Existiert `/dev/cu.<device>` nicht mehr, wird das erste
   `/dev/cu.<prefix>*` genommen. Diese Gerätenamen ändern sich je nach USB-Port.
4. Der Treiber wird anhand von `deviceType` gewählt (Abschnitt 3).
5. Die GPX-Datei wird in die Track-Bibliothek importiert. Danach folgt die Nachbearbeitung (Abschnitt 5).
6. Ergebnisse oder Fehler werden als Alert gemeldet. Texte:
   - „Error communicating with the GPS device. Please check connection and configuration.“
   - „The import finished successfully. However no tracks have been created because your logger does not contain any GPS data.“
   - „%d tracks have been imported.“ oder „… already existing track(s) have been found.“

**Löschen** (`deleteDataFromGPSDevice:`) ist nur erlaubt, wenn eine der folgenden Bedingungen gilt:

- Der Treiber ist `wbt*`, `m241*`, `mtk*` oder `skytraq*`.
- Der Treiber-String enthält `!DEL!`.
- Es ist ein interner Treiber (`*…`).

Sonst erscheint „Deleting is currently only supported for the wbt, mtk and skytraq driver.“

Außerdem gibt es `killAllRunningProcesses` (`killall gpsbabel`) als Abbruch beim Beenden der App.

## 3. Treibertypen (Codierung im `deviceType`-String)

Quelle: `DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`.

### 3.1 gpsbabel-Treiber (kein Präfix)

Der Treibername ist ein gpsbabel-Eingabeformat. Aufruf (Shell über `system()`, Arbeitsverzeichnis `$TMPDIR`):

```
gpsbabel -t -w -i <type>[<additionalArgs>] -f "/dev/cu.<device>" <filter> -o gpx -F <out.gpx>
```

- Beginnt `additionalArguments` mit `,`, wird der Teil direkt an `-i <type>` angehängt.
  Das sind Format-Optionen, z. B. `,baud=38400,initbaud=38400`. Sonst wird er ans Ende der Kommandozeile angehängt.
- `!FILTER!` in `additionalArguments`: Alles danach wird als gpsbabel-Filter eingefügt (`-x …`).
- `#<suffix>` im deviceType: Statt `gpsbabel` wird `gpsbabel<suffix>` aufgerufen. Das ist ein Überbleibsel für mehrere gpsbabel-Versionen.
- Löschen: `-i <type>,erase<additionalArgs>`; bei `skytraq` `-i skytraq,erase,no-output`.
  Erlaubt nur für `wbt`, `mtk`, `skytraq` und `m241`. Sonst liefert die Funktion den Code 254.

Im Direktmodus verwendete gpsbabel-Treiber (siehe Katalog):

| gpsbabel-Format | Geräte (Auswahl) | Löschen | Bemerkung |
|---|---|---|---|
| `mtk` | Qstarz BT-Q1000/1300/BT-100, iBlue 747, Blumax GPS-4044, iTrek Z1, Photomate 887, Transystem 860E, Networx iGeo | ja | MediaTek-Chipsatz, sehr verbreitet |
| `m241` | Holux M-241, GPSport 245 | ja | MTK-Variante von Holux |
| `wbt` | Wintec WBT-100/200/201, G-Rays 2, WSG-1000 | ja | |
| `skytraq` | SkyTraq Venus, Canmore GT-730FL/740FL/750F, Conrad GT-730/750, Navin MiniHomer, Travel Honey, Gisteq DPL900, Dörr | ja | Baudraten-Optionen `baud`, `initbaud` |
| `navilink` | Locosys GT-11/GT-31/BGT-31, NaviGPS | nein | |
| `magellan` | Magellan SporTrak/Meridian | nein | |
| `itracku` | XAiOX iTrackU | nein | |

#### gpsbabel-Versionen und Formatumfang

Ab Version 1.8 hat gpsbabel viele alte Formate entfernt. Dazu gehören gerade die Logger-Treiber `wbt`,
`navilink`, `magellan` und `itracku` sowie die Dateiformate `wintec_tes`, `sbp`, `sbn`, `gopal`,
`alantrl`, `wbt-bin` und `wbt-tk1`. Das betrifft rund 35 Einträge im Katalog.

| myTracks | gpsbabel | Architektur | entfernte Formate vorhanden? |
|---|---|---|---|
| 4.4.0 | 1.9.0 | universal | nein |
| 4.4.3 | **1.7.0** | nur x86_64 | **ja**: „Rückkehr zu 1.7.0, da einige Dateiformate … nicht mehr unterstützt werden“ |
| 4.5.0 (aktuell) | 1.10.0 | universal, ab macOS 11 (Qt 6.5.3) | nein |

⚠️ Folge: Im aktuellen myTracks 4.5.0 bietet die plist die wbt-, navilink-, magellan- und itracku-Geräte
weiterhin an, gpsbabel 1.10.0 kennt diese Formate aber nicht mehr. Diese Geräte funktionieren dort also nicht.

Geprüft wurde das so: Die 1.10.0 aus dem aktuellen Bundle wurde ausgeführt (`gpsbabel -^1` listet 60 Formate).
Die Binaries aus der Historie wurden mit `strings` auf die Formatnamen untersucht.
In 1.7.0 vorhanden sind alle im Katalog genutzten Formate **außer** `cetus` und `coto` (Palm OS).

**gpsbabel 1.7.0** (für gpsloader vorgesehen) ist an zwei Stellen verfügbar:

- Git-Historie, Commit `e0d1f18`: `myTracks/Source/Resources/X86Only/gpsbabel1_7_0`
  (identisch mit `X86Only/gpsbabel` in diesem Commit) und
  `myTracks/Source/Resources/X86Only/QtCoreGpsBabel.framework` (Qt 5.12.9).
- Arbeitskopie: `Import/Apps/GPSBabelFE170.app` (gpsbabel 1.7.0 samt Qt-5-Frameworks).
  `Import/install-gpsbabel170.sh` stellt daraus `gpsbabel` und `QtCoreGpsBabel.framework` zusammen
  (install_name_tool + codesign mit Developer ID).

Eigenschaften: Mach-O **x86_64**, Minimum macOS 10.12. Gelinkt gegen
`@executable_path/../Frameworks/QtCoreGpsBabel.framework/Versions/A/QtCoreGpsBabel`, CoreFoundation,
IOKit und DiskArbitration. Auf Apple Silicon braucht es **Rosetta 2**. Fehlt Rosetta, schlägt der Start
eines Hilfsprozesses mit „Bad CPU type in executable“ fehl. Einen Installationsdialog gibt es dabei nicht.

### 3.2 Interne Treiber (Präfix `*`)

Sie sind in Objective-C implementiert und implementieren das Protokoll `GpsDriver`
(`DsTrackFramework/Source/Classes/GpsDriver/GpsDriver.h`):

```objc
- (NSString*) name;
- (NSArray*)  importTracksFromDevice:(NSString*)device options:(NSDictionary*)options;
- (BOOL)      deleteTracksFromDevice:(NSString*)device options:(NSDictionary*)options;
```

Die Track-Liste wird anschließend als GPX exportiert, und zwar ohne myTracks-Extensions.

#### `*BG728` – Maptaq Trip IQ (`GpsDriver/BG728.m`)

- Seriell über `AMSerialPort` (`GpsDriver/AMSerialPort/`, Fremdbibliothek): **115200 Baud, 8N1**, Lese-Timeout 30 s.
- ASCII-Zeilenprotokoll im NMEA-Stil, Zeilenende `\r\n`. Die Prüfsumme ist das XOR aller Zeichen zwischen `$` und `*`, als zweistellige Hex-Zahl.
- Ablauf:
  1. `$BG728,0,3*3B` fragt die Zeitzone ab. Antwort: commandId 3, Argument 0 = Zeitzone in **Stunden**.
  2. `$BG728,0,16*0F` fragt die Anzahl der Punkte ab. Antwort: commandId 16, Argument 0 = Anzahl.
  3. `$BG728,0,17,<n>*00` fragt Punkt *n* ab (0-basiert). Die Prüfsumme wird hier immer als `00` gesendet; das Gerät ignoriert sie offenbar.
     Antwort: commandId 17. Argumente: `n, hh:mm:ss, MMDDYY, lat, lon, ele`
     (Beispiel: `11:54:02`, `051712`, `51.741158`, `8.680967`, `94`).
     Das Jahr ist `20YY`.
  4. Löschen: `$BG728,1,18*00`. Antwort: commandId 18.
- Antwortformat: `$BG728,<commandCode>,<commandId>,<args…>*<cs>`.
- Fehlerbehandlung: Bei falscher Prüfsumme, fremder Kennung oder unpassender Antwort wird die aktuelle Anfrage erneut gesendet.
  Nach mehr als 128 Leseversuchen ohne passende Antwort bricht der Treiber ab. Lesefehler-Code 100 (Timeout) wird toleriert.
- Ergebnis: **ein** Track. Name = Zeitpunkt des ersten Punkts. Der Zeitzonen-Offset (`timezone * 60` Minuten) wird am Track gespeichert.
  ⚠️ Offen: Es ist nicht geklärt, ob die Gerätezeit UTC oder Lokalzeit ist. Die Alt-App interpretiert den ISO-String ohne Zonenangabe.
  Das muss mit echter Hardware verifiziert werden.

#### `*GNS2000` – GNS 2000 / GNS 2000 plus (`GpsDriver/GNS2000.m`)

- **Bluetooth Classic über IOBluetooth**, nicht über `/dev/cu.*`. Der Gerätepfad wird ignoriert.
  1. Unter `IOBluetoothDevice.pairedDevices` wird das Gerät mit dem Namen `GNS 2000` oder `GNS 2000 plus` gesucht.
  2. Bestehende Verbindung schließen, `openConnection` aufrufen, jeweils 2 s warten.
  3. SDP-Query. Den Service mit dem Namen `GNS GPS` suchen und dessen RFCOMM-Kanal öffnen (`openRFCOMMChannelSync`).
- Das Protokoll ist MTK-basiert mit NMEA-artigen Zeilen und XOR-Prüfsumme. Das Gerät sendet laufend NMEA-Sätze.
  Die erste Zeile, die mit `$` beginnt, gilt als Signal „bereit“. Erst dann wird die Anfrage gesendet.
  - Lesen: `$PGNS,R*<cs>`. Antworten:
    - `$PMTKLOX,0,<anzahlPakete>`: Start.
    - `$PMTKLOX,1,<paketIndex>,<w1>,<w2>,…`: Daten. Je 4 Hex-Wörter (8 Hex-Zeichen) ergeben einen 16-Byte-Datensatz.
    - `$PMTKLOX,2`: Ende.
  - Löschen: `$PGNS,C*<cs>`. Bestätigung: `$PMTK001,…`. Nach mehr als 10 Nicht-`$P`-Zeilen wird die Anfrage wiederholt.
  - Version (ungenutzt): `$PGNS,V,3`.
- **16-Byte-Datensatz** (Little Endian):

  | Offset | Typ | Inhalt |
  |---|---|---|
  | 0 | UInt32 | Unix-Zeitstempel (UTC) |
  | 4 | UInt8 | Fix-Typ; nur 1…4 sind gültig |
  | 5 | Float32 | Breite |
  | 9 | Float32 | Länge |
  | 13 | Int16 | Höhe (m) |
  | 15 | UInt8 | (ungenutzt, vermutlich Prüfsumme) |

  Datensätze aus lauter `FF` gelten als leer und werden übersprungen.
- **Track-Aufteilung**: Ist ein Zeitstempel kleiner als der vorherige, beginnt ein neuer Track.
- Track-Namen: Zeitpunkt des ersten Punkts. Die Zeitzone kommt aus den App-Einstellungen.
- Synchronisation: Die Delegates laufen auf dem Main Thread, der Aufrufer wartet über `NSCondition`.
  Einen Timeout gibt es nicht; die Alt-App kann hängen bleiben.

#### i-GotU (Mobile Action), entfernt in myTracks 4.5.0

Quelle: `git show 3cbc727^:DsTrackFramework/Source/Classes/GpsDriver/IGotUGT800.m` (bzw. `IGotU.m`)
und `git show 3cbc727^:myTracks/Source/Resources/gpslogger.plist`.

Katalog-Einträge vor der Entfernung (alle Typ `usb`):

| Gerät | Treiber | Löschen |
|---|---|---|
| i-GotU GT-100, GT-120, GT-600 | externes `igotu2gpx0.3.0 dump` bzw. `clear` (Shell-Kommando, `driverurl = skip`) | ja |
| i-GotU GT-200e | `igotu2gpx0.3.0 dump` | nein |
| i-gotU GT-800 (und Pro) | interner Treiber `*i-gotUGT800` (`IGotUGT800.m`) | ja |

`igotu2gpx` ist ein externes Open-Source-Programm (GPL). Es lag in den Versionen 0.3.0 und 0.4.0 bei
(Qt 4, boost, libusb 0.1/1.0, **nur x86**). Der Versionshinweis zu 4.5.0 nennt als Grund für die
Entfernung „fehlende Treiber für Apple Silicon“. Tatsächlich fehlten arm64-Builds dieser Programme;
einen Kernel-Treiber gab es nicht.

**Gemeinsames Protokoll** (identisch in `IGotU.m` und `IGotUGT800.m`):

- Befehle beginnen mit `0x93`. Das letzte Byte ist die Prüfsumme: `(0 − Summe aller vorherigen Bytes) mod 256`.
- Eine Antwort beginnt mit `0x93`. Bytes davor werden verworfen.
- Befehle (Bytes nach `0x93`, Rest mit `00` aufgefüllt):

  | Zweck | Befehl | Antwort |
  |---|---|---|
  | NMEA-Ausgabe umschalten | `93 01 01 <mode>`; mode 3 vor dem Auslesen, 0 danach | 3 Byte |
  | Identifikation (USB-Variante) | `93 0A` | 3 Byte, danach 10 Byte: Seriennummer LE32 in Byte 0–3, Modell in Byte 7 (1 = GT-120, 2 = GT-200, 8 = GT-800) |
  | Modell (GT-800) | `93 05 04 00 03 01 9F` | 6 Byte; Byte 5 == `0x17` bedeutet GT-800 Pro |
  | Anzahl Punkte | `93 0B 03 00 1D` | GT-800: 6 Byte, Anzahl = `((b[3] & 3) << 16) + BE16(b[4..5])`; USB: 3 Byte, Anzahl = `BE16(b[1..2])` |
  | Speicher lesen | `93 05 07 <sizeHi> <sizeLo> 04 03 <pos 24 Bit BE>` | 3 Byte, danach `size` Datenbytes |

- Die Daten beginnen bei Adresse `0x1000` und werden in Blöcken von `0x1000` Byte gelesen, bis
  `Anzahl × 32` Byte erreicht sind.
- **Datensatz, 32 Byte, Big Endian:**

  | Offset | Inhalt |
  |---|---|
  | 0 | Flags: `0x04` Wegpunkt, `0x10` Navigationsdaten ungültig, `0x40` Track-Start. Der Wert `0xF1` markiert einen Debug-Datensatz mit ASCII-Text ab Byte 6. |
  | 1 | High-Nibble: **Jahr mod 16**; Low-Nibble: Monat |
  | 2–3 | Tag = `b2 >> 3`; Stunde = `(b2 & 7) * 4 + (b3 >> 6)`; Minute = `b3 & 0x3F` |
  | 4–5 | Millisekunden (BE16); Sekunde = Wert / 1000 |
  | 8–11 | Höhe aus Luftdruck, Int32 / 100 |
  | 12–15 | Breite, Int32 / 1e7 |
  | 16–19 | Länge, Int32 / 1e7 |
  | 20–23 | Höhe GPS, Int32 / 100 (wird verwendet; die Luftdruckhöhe ist deaktiviert) |
  | 29 | Low-Nibble: genutzte Satelliten; High-Nibble: maximal gefundene Satelliten |
  | 30 | „weight criteria“ (ungenutzt) |

- Gültigkeit: nicht ungültig, genutzte Satelliten > 4 und maximal gefundene > 0 (GT-800).
  Der USB-Code verlangt nur genutzte Satelliten > 0.
- Das Flag „Track-Start“ beginnt einen neuen Track. Wegpunkte werden zu Trackpunkten mit dem Namen „WPT“.
- ⚠️ Das Jahr wird relativ zum aktuellen Jahr rekonstruiert (letzte 16 Jahre). Bei sehr alten Daten ist es mehrdeutig.
- ⚠️ Die Zeit wird ohne Zonenangabe interpretiert. Vermutlich ist es UTC; mangels Testgerät ist das nicht verifiziert.

**GT-800** (`IGotUGT800.m`): seriell (`/dev/cu.*`) mit **9600 Baud, 8N1**, ohne Flusskontrolle,
nicht-kanonischer Modus, Lese-Timeout 5 s. Ein Befehl ist **16 Byte** lang.
Löschen (`purgeMemory`):

1. Von Block `0x6FF` abwärts bis 1 wird je mit `Speicher lesen` (16 Byte bei `i × 0x1000`) gesucht,
   bis der erste Block gefunden ist, der nicht nur aus `FF` besteht.
2. Ab diesem Block wird für jeden Block die folgende Sequenz gesendet:
   - `93 06 04 00 00 01 06`, erwartete Antwort `93 00 00`
   - `93 06 07 00 00 04 20 <pos 24 Bit>`, erwartete Antwort 3 Byte
   - `93 05 04 00 01 01 05` so lange wiederholen, bis die Antwort `93 00 01 00` lautet
3. Danach muss der Anwender den Logger abziehen, damit er neu startet. Die Alt-App zeigt dafür einen Hinweis.

Die Bedeutung der Schreibbefehle ist nicht dokumentiert; im Code heißen sie `sendUnknownWriteCommand`.

**GT-100/120/200e/600** (Vorlage `IGotU.m`): USB-Vendor `0x0DF7`, Product `0x0900`. Der GT-800 hat
über USB die Product-ID `0x0B80`.

- Ein Befehl wird in **zwei 8-Byte-Hälften** als Control-Transfer gesendet:
  `bmRequestType 0x21, bRequest 0x09, wValue 0x0200, wIndex 0`. Das entspricht einem HID-`SET_REPORT`.
- Die Prüfsumme steht im letzten Byte der zweiten Hälfte und umfasst beide Hälften.
- Antworten kommen über die Interrupt-/Bulk-Pipe.
- `IGotU.m` war **unfertig** und wurde in keinem plist-Eintrag verwendet: Die Product-ID ist fest auf
  `0x0B80` gesetzt, gelesen werden höchstens 12 Blöcke, und Löschen ist nicht implementiert.
- Hypothese, nicht verifiziert: Weil es ein HID-Gerät ist, lässt es sich über IOHIDDevice ohne Kext ansprechen.

### 3.3 Shell-Kommando-Treiber (Präfix `!`)

Der deviceType ist eine Shell-Kommandozeile. Ein optionales `!DEL!` trennt das Lösch-Kommando ab:
`!<importCmd>!DEL!<deleteCmd>`. Platzhalter (`replaceTemplates:` in `GPSBabel.m`):

| Platzhalter | Ersetzung |
|---|---|
| `$BUNDLE` | Pfad des App-Bundles |
| `$APP_BUNDLE` | veraltet, wird zu `$BUNDLE/Contents/Resources` (siehe `correctSetting:`) |
| `$TMPDIR` | Temp-Verzeichnis |
| `$DEVICE` | `/dev/cu.<device>` (für die Shell gequotet) |
| `$GPX` und `$GPX_NO_EXT` | Ziel-GPX-Datei mit bzw. ohne Endung |
| `$INPUTFILE` | Eingabedatei (Dateimodus) |

Erfolgskriterium beim Import: Die Zieldatei existiert und ist mindestens 10 Byte groß.

Verwendete Hilfsprogramme (alle unter `myTracks/Source/Resources/`):

| Geräte | Hilfsprogramm | Sprache / Lizenz | Bemerkung |
|---|---|---|---|
| Royaltek RGM-3800, GOSGET S1, RBT-2300 | `rgm3800-rev25.py`, `rbt2300.py` (`-d $DEVICE trackx 0-` bzw. `erase all`) | Python 2, GPLv3 (Karsten Petersen) | RBT-2300 hat ein zusätzliches Feld in `GetInfo` |
| Gisteq PhotoTrackr DPL700/CD111, XAiOX iTrackU (Nemerix/SiRF III) | `iTU4l/iTU4l.pl` + `iTU4l/sr2x.pl` (vorher `stty 115200 cs8 raw`) | Perl, GPLv2 (Hartmut Schimmel) | Variante über `-i p`, `-i n` oder `-i s` |
| MainNav | `mainnav-reader-0.5/mainnavdist/…` | Python 2, BSD-2 (Dennis Keitzel) | Löschen mit `-p` |
| Holux GPSport 245 (Alternative) | zweistufig: `gpsbabel -i m241` und danach `-i m241-bin` | gpsbabel | |

⚠️ **Python 2 ist seit macOS 12.3 nicht mehr vorhanden, und Perl ist von Apple als veraltet markiert.**
Diese Treiber funktionieren auf aktuellen Systemen in der Alt-App faktisch nicht mehr.

Die Variante „Holux GPSport 245 – alternative“ ist ebenfalls ein Shell-Kommando, braucht aber keine Skriptsprache:

1. `gpsbabel -i m241 -f $DEVICE -o csv -F $TMPDIRm241.csv`; dabei entsteht als Nebenprodukt `data.bin` im Arbeitsverzeichnis.
2. `gpsbabel -t -w -i m241-bin -f $TMPDIRdata.bin -o gpx -F $GPX`

## 4. Dateimodus (USB-Speicher / SD-Karte)

- Der Anwender wählt eine oder mehrere Dateien aus. Konvertiert wird mit
  `gpsbabel -t -w -i <gpsFileFormat> -f <in> -o gpx -F <out> <args> 2>&1`, stderr wird als Fehlertext angezeigt.
- Beginnt `gpsFileAdditionalArguments` mit `!`, ist es ein Shell-Kommando mit Platzhaltern (wie in 3.3).
- **NMEA**: Mehrere Dateien werden vor der Konvertierung aneinandergehängt (`cat`), außer wenn das UserDefault
  `DoNotMergeNMEAFiles` gesetzt ist. Zeilen, die mit `@` beginnen, werden entfernt (Sony GPS CS-1/CS-3).
- Enthält das Ergebnis keine Tracks, folgt ein zweiter Versuch mit `gpsbabel -i gpx … -x transform,trk=wpt`:
  Wegpunkte werden zu einem Track.
- Hilfsprogramme: `suuntoconvert/ambit2gpx.py` (Suunto Ambit XML/SML, Python 2), `wsg2000/wsg2000.c`
  (Wintec WSG-2000 `.NAL`, C, GPL/CC-BY-SA, Greg A. Woods), `fit2tcx` (Garmin).
  Für TCX gibt es `-i gtrnctr -x transform,rte=trk`, für IGC `-i igc`.
  ⚠️ Der IGC-Eintrag in der plist enthält einen Tippfehler (`i-o gpx` statt `-o gpx`).
- Die Liste der angebotenen gpsbabel-Dateiformate (70 Einträge) steht in `GPSBabel.m` (`gpsBabelFileFormats[]`).
- `cetus` und `coto` (Palm OS) sind schon in gpsbabel 1.7.0 nicht mehr enthalten. Diese Katalog-Einträge sind tot.

**WSG-2000 `.NAL`** (`myTracks/Source/Resources/wsg2000/wsg2000.c`, Greg A. Woods, CC-BY-SA/GPLv2):
eigenes C-Programm (Bundle-ID `info.stichling.wsg2000`). Das Format besteht aus festen Datensätzen
von **32 Byte**, Little Endian:

| Feld | Inhalt |
|---|---|
| Flags (16 Bit) | Bit 0 Track-Start, Bit 1 Wegpunkt |
| Zeit (32 Bit, bitgepackt) | Sekunde 6 Bit, Minute 6 Bit, Stunde 5 Bit (vermutlich UTC) |
| Datum (32 Bit, bitgepackt) | Tag 5 Bit, Monat 4 Bit, Jahr 6 Bit (+2000) |
| Breite, Länge | Int32 / 1e7 |
| Höhe | UInt16, Meter |
| Temperatur | Int8, °C |
| Luftdruck | UInt16, mbar |
| Trittfrequenz, Puls | UInt8 |
| Steigung | Int8, Grad |
| Kompass, Roll, Yaw | Int16 |
| Geschwindigkeit | UInt8, km/h |
| Benutzer | UInt8, 0–3 |
| Auffüllung | 16 Bit |

Die genaue Bit-Anordnung steht in der Struktur `nal_data32_le` in `wsg2000.c`.

**Wintec WPL 1000 / Navilock NL-456DL Easy Logger**, entfernt in myTracks 4.5.0: Datei `nvpipe.dat` vom
Gerät. Gelesen wurde sie mit `wpl1000reader`, einem externen Programm (C++, nur x86_64, Oliver Lau 2008/09,
„Alle Rechte vorbehalten“, **ohne Quellcode**). Das Binary steht noch unter
`git show 3cbc727^:myTracks/Source/Resources/X86Only/wpl1000reader`; Option `-m` erzeugt eine Datei pro Track.

## 5. Nachbearbeitung beim Import

Quelle: `DsTrackFramework/Source/Classes/ImportExport/TrackLibraryGPX.m`, `GpxImportConfiguration`.

- **GPS-Week-Rollover-Korrektur**: Liegt ein Punkt mehr als 512 Wochen in der Vergangenheit, werden
  1024 Wochen addiert. Das wird so lange wiederholt, bis die Bedingung nicht mehr zutrifft.
  Abschaltbar per UserDefault `DontCorrectWeekRollover`. Für ältere MTK-Logger ist das relevant.
- **Zeitzone**: Ist am Track keine Zeitzone gesetzt, nimmt die Alt-App die Zeitzone aus den Einstellungen.
  In GPX sind Zeiten immer UTC; für gpsloader ist das nur relevant, wenn Geräte Lokalzeit liefern (BG728?).
- **Dublettenerkennung**: Track-ID `logger:<start>-<ende>`. Das ist myTracks-spezifisch und wird in gpsloader eventuell nicht benötigt.
- GPX-Export ohne myTracks-Extensions (`GpxExportConfiguration.exportMytracksExtensions = NO`).

## 6. Gerätewahl und Einrichtungsassistent

Quelle: `myTracks/Source/Classes/Controller/GpsLoggerWizard.m`,
`NewControllers/Preferences/PrefGpsDevicesViewController.swift`.

- Geräteliste: alle Einträge `/dev/cu.*`.
- Assistent mit Suche über die Gerätenamen aus `gpslogger.plist`. Die Schritte hängen vom Typ ab:
  - **USB**: Der Anwender zieht das Gerät ab, und die vorhandenen `cu.*` werden gemerkt. Dann schließt er es an,
    wartet 5 s und sieht ein neues `cu.*`. Bevorzugt wird `SLAB_USBtoUART`. Wird nichts gefunden,
    verlinkt der Assistent die Treiber-Downloadseite (`driverurl`, allgemein `http://www.mytracks4mac.info/drivers`).
  - **Bluetooth**: Der Anwender wählt aus der `cu.*`-Liste (das Gerät muss vorher gekoppelt sein).
  - `driverurl == "skip"`: keine Gerätewahl, Gerät `auto`.
- Die USB-Seriell-Chips der Logger sind typischerweise Silicon Labs CP210x (`SLAB_USBtoUART`), Prolific PL2303
  (`PL2303-*`, `usbserial-*`) oder CDC-ACM (`usbmodem*`). Bisher waren dafür teils Hersteller-Kexts nötig,
  die nur auf Intel-Macs laufen. Das ist der Anlass für die Auslagerung.
  (Aktuelle macOS-Versionen bringen für CP210x, PL2303, FTDI und CDC-ACM eigene DriverKit-Treiber mit.
  Welche Geräte damit ohne Zusatztreiber laufen, ist noch zu prüfen.)
- Bluetooth-Logger, außer GNS2000, laufen ausschließlich über den seriellen Port `/dev/cu.<Name>`,
  den macOS nach dem Koppeln anlegt. Mehr konnte die Alt-App nicht.

## 7. Nicht zu übernehmende Funktionen

- Track-Bibliothek, Karten, Geotagging, Dublettenerkennung, Lizenzprüfung (`stripIfNoLicense`).
- LoadMyTracks-Anbindung (Typ `loadmytracks`, 37 Geräte, hauptsächlich Garmin).
- Echtzeit-Tracking (`RealtimeTracking.m`: `gpsbabel -T -i NMEA -f /dev/cu.<device> -o csv -F -`), außer es wird ausdrücklich gewünscht.
- Allgemeine GPX/KML/LOC/GPI-Konvertierungen und `simplifyFile` aus `GPSBabel.m`. Sie dienen der Track-Verwaltung, nicht dem Logger-Auslesen.
- Logger-Konfigurationen aus myTracks (Abschnitt 1).
- Alle Treiber, die auf Skriptsprachen basieren (Abschnitt 3.3), sowie `ambit2gpx.py` und `fit2tcx` (Perl).

## 8. Bekannte Schwächen der Alt-Implementierung (nicht nachbauen)

- Shell-Aufrufe über `system()` und `popen()` mit String-Konkatenation (Quoting- und Injection-Risiko).
- Keine echte Fortschrittsanzeige und kein sauberer Abbruch (nur `killall gpsbabel`).
- GNS2000 kann ohne Timeout endlos warten. BG728 blockiert synchron im Lesethread.
- Manuelle Speicherverwaltung (MRC) und Objective-C-Singletons.
- Abhängigkeit von Python 2 und Perl.
