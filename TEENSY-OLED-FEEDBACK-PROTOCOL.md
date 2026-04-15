# Teensy OLED Feedback Protocol (SC -> Teensy)

## Ziel

Ein stabiles, leicht implementierbares MIDI-CC-Protokoll fuer 128x64 OLED (SSD1306/SH1106), ohne Pi-CPU-Mehrlast im Rendering.

## Transport

- Richtung: `SuperCollider (sclang) -> Teensy`
- Kanal: MIDI Channel 1 (0-basiert in SC: channel 0)
- Datentyp: MIDI CC (`0..127`)

## OLED Frame Mapping (empfohlen)

- `CC 70` -> Master Volume Bar (`0..127`)
- `CC 71` -> Filter Cutoff Bar (`0..127`, musikalisch gemappt)
- `CC 72` -> DnB Chaos Bar (`0..127`)
- `CC 73` -> Ambient Reverb Bar (`0..127`)
- `CC 74` -> Tempo (`BPM`, skaliert/clamped auf `0..127`)
- `CC 75` -> Status Flags bitpacked:
  - Bit 0: SAFE mode
  - Bit 1: Auto Scene ON
  - Bit 2: MIDI Feedback ON
  - Bit 3: DnB Player ON

## Timing-Regeln

- OLED-Frame-Updates auf ca. `8..20 Hz` begrenzen.
- Bei harten Zustandswechseln (Preset, Panic, Scene-Change) einmalige Sofort-Frames senden.
- Deadband pro CC behalten, damit Display nicht flackert.

## Teensy-Seite (C++ Orientierung)

- Eingehende CCs puffern (letzten Wert pro CC).
- Display-Zeichnen in festem Refresh-Loop (z. B. 20-40 ms), nicht pro CC-Interrupt.
- Bei `CC75` optional Status-Icons/Blitz-Events triggern.