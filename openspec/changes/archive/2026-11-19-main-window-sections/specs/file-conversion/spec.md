## MODIFIED Requirements

### Requirement: Dateien auswählen
Die App SHALL einen Befehl „Dateien konvertieren…“ im Menü „Ablage“ mit dem Kurzbefehl ⌘O und als Schaltfläche im Bereich „Dateien konvertieren“ anbieten; der Bereich SHALL außerdem eine Ablagefläche für Dateien zeigen. Der Befehl SHALL auf diesen Bereich schalten und einen Dateidialog öffnen, in dem eine oder mehrere Dateien gewählt werden können. Dateien, die auf das Hauptfenster gezogen werden, SHALL die App in jedem Bereich annehmen, auf den Bereich „Dateien konvertieren“ schalten und konvertieren.

#### Scenario: Auswahl über das Menü
- **WHEN** der Anwender „Ablage > Dateien konvertieren…“ wählt und zwei NMEA-Dateien auswählt
- **THEN** startet die Konvertierung dieser beiden Dateien

#### Scenario: Drag & Drop
- **WHEN** der Anwender eine IGC-Datei aus dem Finder auf das Hauptfenster zieht
- **THEN** startet die Konvertierung dieser Datei

#### Scenario: Ordner gezogen
- **WHEN** der Anwender einen Ordner auf das Hauptfenster zieht
- **THEN** nimmt die App ihn nicht an

#### Scenario: Drag & Drop im Gerätebereich
- **WHEN** der Bereich „Gerät auslesen“ gezeigt wird und der Anwender eine NMEA-Datei auf das Fenster zieht
- **THEN** zeigt das Fenster den Bereich „Dateien konvertieren“, und die Konvertierung startet
