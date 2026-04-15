# DnB Timing Note (wichtig)

## Kernregel
Du bist **nicht** auf 170 BPM festgelegt. Tempo darf live variieren.

Damit Breakbeat-Slices trotzdem tight bleiben, gilt:

- Trigger-Zeit kommt von der `TempoClock`.
- Sample-Playback-Rate muss dynamisch mit dem aktuellen Clock-Tempo mitlaufen.

## Formel (verbindlich merken)

`rate = currentBPM / originalSampleBPM`

mit:
- `currentBPM = (clock.tempo * 60)`  // tempo in beats/sec -> BPM
- `originalSampleBPM` = einmalig definierter BPM-Wert des Original-Samples

## Warum das wichtig ist
- Ohne dynamische Rate entstehen bei Tempoänderung Lücken/holpriger Groove.
- Mit dynamischer Rate bleibt das Sample bei jedem Tempo im Raster.
- Nebenwirkung (gewollt): klassischer Pitch-Shift-Charakter wie bei oldschool Samplern.

## Projekt-Entscheidung
- `originalSampleBPM` als expliziter Parameter/Variable im Pattern halten.
- Rate in `Pbind` immer dynamisch über `Pfunc` aus der aktiven Clock berechnen.
