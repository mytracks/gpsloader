## ADDED Requirements

### Requirement: Bereiche des Hauptfensters
Das Hauptfenster SHALL in der Werkzeugleiste einen Umschalter mit den Bereichen „Dateien konvertieren“ und „Gerät auslesen“ zeigen und darunter nur den gewählten Bereich. Das Menü „Darstellung“ SHALL beide Bereiche mit ⌘1 und ⌘2 anbieten. Die App SHALL den zuletzt gewählten Bereich beim nächsten Start wieder zeigen; beim ersten Start SHALL „Gerät auslesen“ gewählt sein.

#### Scenario: Erster Start
- **WHEN** die App zum ersten Mal startet
- **THEN** zeigt das Hauptfenster den Bereich „Gerät auslesen“, und im Umschalter ist dieser Bereich gewählt

#### Scenario: Bereich merken
- **WHEN** der Anwender „Dateien konvertieren“ wählt und die App neu startet
- **THEN** zeigt das Hauptfenster den Bereich „Dateien konvertieren“

#### Scenario: Tastenkürzel
- **WHEN** der Anwender im Bereich „Dateien konvertieren“ ⌘2 drückt
- **THEN** zeigt das Hauptfenster den Bereich „Gerät auslesen“
