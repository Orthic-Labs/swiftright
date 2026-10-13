#!/usr/bin/env python3
"""Source admission checks for F10 reader packet; no native/effect execution."""
from __future__ import annotations

import ast
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "trusted-reader-report.py"


def main() -> int:
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"), filename=str(SOURCE))
    source = SOURCE.read_text(encoding="utf-8")
    assert "ArchiveByteReader" in source
    assert "verify_windows_exit_admission" in source
    assert "windowsArchives" in source and "windowsExitProof" in source
    assert '"nativeParity": "held"' in source
    assert '"sourceMutations": 0' in source
    forbidden = ("subprocess", "ssh", "scp", "CreateProcess", "Start-Process", "fcntl.flock")
    assert not any(token in source for token in forbidden)
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    assert any(isinstance(n.func, ast.Name) and n.func.id == "verify_windows_exit_admission" for n in calls)
    assert any(isinstance(n.func, ast.Name) and n.func.id == "ArchiveByteReader" for n in calls)
    print(json.dumps({"status": "PASS", "controls": ["real-reader-call", "real-exit-admission-call", "exact-proof-fields", "observation-only", "no-effect-apis"]}, sort_keys=True))


if __name__ == "__main__":
    main()
