import os

file_path = 'Chords_Scales.pd'

with open(file_path, 'r') as f:
    content = f.read()

# 1. Inlets in globale Receiver umwandeln (x-Koordinaten aus deiner Datei)
content = content.replace('#X obj 200 30 inlet;', '#X obj 200 30 r cosmic-w;')
content = content.replace('#X obj 275 30 inlet;', '#X obj 275 30 r wonder-w;')
content = content.replace('#X obj 350 30 inlet;', '#X obj 350 30 r hopeful-w;')
content = content.replace('#X obj 425 30 inlet;', '#X obj 425 30 r koto-w;')
content = content.replace('#X obj 500 30 inlet;', '#X obj 500 30 r raga-w;')
content = content.replace('#X obj 575 30 inlet;', '#X obj 575 30 r pelog-w;')
content = content.replace('#X obj 650 30 inlet;', '#X obj 650 30 r safir16-w;')

# 2. Mathe-Bug beheben: Skalierung entfernen, aber PD-Inlets (Kabel) bewahren
content = content.replace('expr $f1/$f2*100;', 'expr $f1+($f2*0);')

with open(file_path, 'w') as f:
    f.write(content)

print("✅ Chords_Scales.pd wurde erfolgreich und sicher gepatcht!")