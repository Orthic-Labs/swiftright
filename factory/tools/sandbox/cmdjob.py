#!/usr/bin/env python3
"""cmdjob.py SCRIPT.ps1 [--timeout SEC] [--out DIR]: like `client.py command` for a script file, with a caller-chosen job timeout (client.py command is fixed at 300 s)."""
import argparse, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import client
ap = argparse.ArgumentParser(); ap.add_argument("script"); ap.add_argument("--timeout", type=int, default=600); ap.add_argument("--out", default=None)
a = ap.parse_args()
out = Path(a.out or f"sandbox-cmd-{client.time.strftime('%Y%m%d-%H%M%S')}")
jid, st, res = client.run_job("command", dict(script=Path(a.script).read_text()), out, a.timeout)
print(st.get("state"), res)
print((out / "out.txt").read_text(errors="replace") if (out / "out.txt").is_file() else "")
