"""Prepare r13 export with unambiguous PowerShell path separators."""
from pathlib import Path

root = Path(__file__).resolve().parent
source = (root / 'prepare-export.py').read_text()
for old, new in (
    ('sr0-r13-capture-held-reader-v1', 'sr0-r13-capture-held-reader-v2'),
    ('sr0-r13-export-r1', 'sr0-r13-export-r3'),
    ('capture-held-predicate-v13.ps1', 'capture-held-predicate-v14.ps1'),
    ('test-capture-held-controls-v1.ps1', 'test-capture-held-controls-v2.ps1'),
    ('export-native-r1.ps1', 'export-native-r3.ps1'),
    (".Replace('\\','/')", '.Replace([char]92,[char]47)'),
):
    assert old in source
    source = source.replace(old, new)
exec(compile(source, str(root / 'prepare-export.py'), 'exec'))
