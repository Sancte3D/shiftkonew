from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent
file_path = ROOT / "Chords_Scales.pd"

if not file_path.exists():
    print(f"❌ Datei nicht gefunden: {file_path}")
    sys.exit(1)

content = file_path.read_text()
original = content

replacements = [
    ("#X obj 200 30 inlet;", "#X obj 200 30 r cosmic-w;"),
    ("#X obj 275 30 inlet;", "#X obj 275 30 r wonder-w;"),
    ("#X obj 350 30 inlet;", "#X obj 350 30 r hopeful-w;"),
    ("#X obj 425 30 inlet;", "#X obj 425 30 r koto-w;"),
    ("#X obj 500 30 inlet;", "#X obj 500 30 r raga-w;"),
    ("#X obj 575 30 inlet;", "#X obj 575 30 r pelog-w;"),
    ("#X obj 650 30 inlet;", "#X obj 650 30 r safir16-w;"),
    ("expr $f1/$f2*100;", "expr $f1+($f2*0);"),
]

applied = 0
for src, dst in replacements:
    if src in content:
        content = content.replace(src, dst)
        applied += 1

if content == original:
    print("ℹ️ Keine Änderungen nötig.")
    sys.exit(0)

backup_path = file_path.with_suffix(".pd.bak")
shutil.copyfile(file_path, backup_path)
file_path.write_text(content)

print(f"✅ Patch angewendet ({applied} Ersetzungen). Backup: {backup_path.name}")