"""Derive bounded full Text20 raw export from proven Rectangle20 export."""
from pathlib import Path

root = Path(__file__).resolve().parent
source = root.parent / 'pilot-rectangle-fixed-root-v2/export-count20-r4.ps1'
text = source.read_text()
for old, new in (
    ('rectangle-fixed-r11-v2', 'text-mta-r11-count20-r10'),
    ('count20-r4', 'count20-r10'),
    ('$files.Count -ge 1024', '$files.Count -ge 2048'),
):
    assert old in text
    text = text.replace(old, new)
with (root / 'export-count20-r10.ps1').open('x') as f:
    f.write(text)
print('prepared bounded full Text20 raw export; nativeActions=0')
