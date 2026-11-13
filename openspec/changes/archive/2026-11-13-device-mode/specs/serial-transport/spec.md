## ADDED Requirements

### Requirement: Baudrate wechseln
Ein geöffneter Port SHALL seine Baudrate auf jede unterstützte Rate umstellen können, ohne geschlossen zu werden. Eine nicht unterstützte Rate MUST mit einem Protokollfehler abgelehnt werden.

#### Scenario: Wechsel nach der Verhandlung
- **WHEN** ein Treiber den Port mit 9600 Baud öffnet und danach auf 115200 Baud umstellt
- **THEN** laufen alle weiteren Lese- und Schreibvorgänge mit 115200 Baud
