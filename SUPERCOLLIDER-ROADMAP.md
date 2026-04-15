# SuperCollider Verbesserungs-Roadmap (Autonom umgesetzt)

## Zielbild
- Stabiler Live-Betrieb ohne Audio-Spikes oder Device-Abstuerze.
- Musikalisch hoerbare, nicht-statische Evolution ohne starre Loops.
- Klare Performance-Oberflaeche mit sicheren Parametergrenzen.

## Entscheidungsmatrix (Machen / Nicht machen)
- **Machen**: harte DSP-Sicherheitsgrenzen (`clip2`, `Limiter`, `Compander`, `Lag`)  
  - Grund: direkter Schutz vor Earrape und Knacksern.
- **Machen**: Weight-basierte Skalenwahl auf `noteTrig` statt langsamer Hintergrund-Clock  
  - Grund: Slider `Cosmic/Wonder/...` werden sofort musikalisch hoerbar.
- **Machen**: Chaos-Modulation statt rein periodischer LFO-only-Logik  
  - Grund: weniger Wiederholung, organischere Langzeitentwicklung.
- **Machen**: Live-UI mit Slidern/Knobs/Buttons + sichere Ranges  
  - Grund: produktive Live-Performance ohne riskante Extremwerte.
- **Spaeter machen**: Vollstaendiger Bus/Group-Routing-Umbau in getrennte Source/FX-Synths  
  - Grund: sinnvoll fuer grosse Sessions, aber hoehere Refactor-Komplexitaet.
- **Nicht jetzt**: Komplett auf externe Quarks (MarkovSet/MathLib) umstellen  
  - Grund: Abhaengigkeitsrisiko, fuer den aktuellen Klanggewinn nicht notwendig.
- **Nicht jetzt**: Uebermaessige Rhythmus-Fraktalisierung (L-System-first)  
  - Grund: kann Ambient-Fluss unnötig fragmentieren; erst als optionaler Modus.

## Bereits implementiert (dieser Stand)
- Audio-Device-/Server-Start gehaertet (Output-fokussiert, stabile Optionen).
- Live-GUI mit Slidern, Knobs, Toggles und Restart/Free.
- Layer-Rebalancing (Texture/Noise runter, Notes hoerbarer).
- Harte Caps und Master-Safety in DSP-Kette.
- Weight-Entscheidung pro Note-Trigger.

## Jetzt neu implementiert
- Chaotische Mikro-Modulation fuer Tonhoehe/Timing zur Anti-Loop-Organik.
- Safe/Wild-Morph-Parameter als Zukunftsanker (intern vorbereitet).

## Nächste automatische Schritte (in Reihenfolge)
1. Optionaler `SAFE/WILD` Button in der UI (ein Klick, zwei Gain-Profile).
2. Optionaler `NOTES SOLO / FULL MIX` A/B-Schalter fuer schnelles Voicing.
3. Optionales getrenntes Source/FX-Bus-Routing fuer noch saubereres Gain-Staging.

## Neue Inputs aus 2026-04-15 (zusätzlicher Dokumenten-Ordner)
- **Machen (Software, jetzt/prioritär):**
  - MIDI-Glättung weiter haerten (Soft-Takeover + Deadband/Jitter-Filter).
  - GUI weiter auf performante Live-Bedienung trimmen (musikalische Ranges, klare Makros).
  - Chaos + stochastische Steuerung als Anti-Loop-Strategie beibehalten.
  - Routing-/Gain-Staging Richtung Source/FX-Trennung weiterentwickeln.
- **Dokumentieren/Merken (Hardware, spaeter):**
  - Teensy 4.x strikt 3.3V-only, keine 5V-Toleranz an I/O.
  - Fader-Standard: 10k linear, Multiplexing via CD74HC4067, saubere gemeinsame Masse.
  - Pi 5 + aktive Kühlung als Ziel-Hardware, getrennte/entkoppelte Sensor-Strompfade.
  - PCB-Regeln fuer Signalintegrität (analog/digital sauber trennen, Grounding diszipliniert).
  - Headless-Betrieb: sichere Shutdown-Strategie statt Stromziehen (optional OverlayFS prüfen).

## Backlog (geplant)
- Source/FX-Bus-Refactor mit `Group.head/tail` für deterministische Order-of-Execution.
- Controller-Profilmanager (MIDI-Learn + Profile speichern/laden pro Hardware-Layout).
- Betriebsdoku `HARDWARE-AND-DEPLOYMENT.md` (Teensy/Pi-Stromversorgung, Shutdown, Verkabelung).

## Audio-Hardware Entscheidungen (neu)
- **Default-Ausgabeziel:** integrierte Lautsprecher, aber **nicht auf ein spezifisches Modul hardcoden**, bis finale Auswahl getroffen ist.
- **Kopfhörer-Switchover:** mechanisch via switched jack (ohne Software-Logik, ohne Reboot).
- **Bluetooth:** als optionales Profil, nicht als primärer Live-Ausgangspfad.
- **Power:** USB-C Dauerstrom als Standard; Akku nur bei nachgewiesener Spannungsstabilität.
- **AUX-In:** nur mit ADC-fähiger Audio-Hardware; danach `SoundIn.ar(...)`-Pfad als optionales Processing-Feature.
- Detailplanung/Notizen in `HARDWARE-AUDIO-STRATEGY.md`.

## Kommunikations-Architektur (ergänzt)
- End-to-End Kette dokumentiert: `Hardware -> Teensy -> USB-MIDI -> sclang -> scsynth`.
- Verantwortlichkeiten klar getrennt:
  - Debounce/Jitter auf Hardware/Teensy
  - Mapping/Encoder-Zustand in sclang
  - Glättung im Audioserver
- In der SC-Engine umgesetzt:
  - Absolute CC-Mappings (mit Pickup + Deadband)
  - Relative Encoder-Mappings (Two's Complement-kompatible Dekodierung)

## Pro-Features (finale Instrumenten-Phase)
- **Visuelles Feedback (Headless):**
  - Bidirektionale Kommunikation einplanen (SC -> Teensy via MIDI-Out).
  - OLED/LED-Feedback auf Teensy-Seite (Werte, Modulationsstatus).
  - Ziel: nicht mehr "blind" performen.
- **Externe Studio-Integration:**
  - 6.35mm Audio-Jacks (TS/TRS) + saubere Erdung.
  - Klassische MIDI-DIN IN/OUT inkl. galvanischer Isolation bei MIDI-IN.
- **Mechanik/Chassis-Qualität:**
  - Panel-Mount bevorzugen (Last auf Gehäuse, nicht auf PCB).
  - M3-Standoffs und Frontplatten-Mechanik als Pflicht für Bühnenfestigkeit.

## Ergänzungen aus Ordner 2026-04-15T105911Z
- Drei-Phasen-Vorgehen wird bestätigt und bleibt verbindlich (Code -> PoC -> finale Hardware).
- Audio-I/O Qualität:
  - TRS symmetrisch als Standard für professionelle/störarme Verkabelung.
  - TS nur für kurze, einfache Strecken.
- DIN-MIDI:
  - MIDI-IN isoliert auslegen (Optokoppler-Pfad), MIDI-OUT nach Standard treiben.
- Mechanik:
  - Panel-Mount + stützende Gehäusemontage als Pflicht.
- Bidirektionalität:
  - SC-MIDI-Out Rückkanal für OLED/LED-Status auf Teensy als nächster Ausbau.

## Umsetzungsfahrplan (verbindlich merken)
1. **Phase 1: Code & Sound** – Klangarchitektur und Live-Engine perfektionieren.
2. **Phase 2: Proof of Concept** – Teensy + wenige Fader auf Breadboard, Mapping verifizieren.
3. **Phase 3: Hardware/PCB** – erst nach stabilem PoC Platine/Finalgehäuse auslegen.
4. **Phase 4: Pro-I/O & Chassis** – TRS/DIN/Panel-Mount/Bidirektionales Feedback integrieren.

## DnB Timing Merkregel
- Breakbeat-Rate bei Tempoänderung immer dynamisch an die aktive Clock koppeln:
  - `rate = (clock.tempo * 60) / originalSampleBPM`
- Dokumentiert in `DNB-TIMING-NOTES.md`.
