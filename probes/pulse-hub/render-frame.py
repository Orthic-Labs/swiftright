#!/usr/bin/env python3
"""usage: render-frame.py <exe on the Dell> <1> <out dir> <renderer dll on the Dell> : ONE Sandbox interact job for the frame the guest counter holds (set it with setframe.sh first).
HUB_WAIT_MS (default 6000) is the wait before the PrintWindow shot; the first-frame blank retry uses 15000."""
import sys, json, os
sys.path.insert(0, "/Volumes/D/claude/swiftright/factory/tools/sandbox")
import client
exe, frames, out, renderer = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
steps = [{"op": "wait", "ms": int(os.environ.get("HUB_WAIT_MS", "6000"))}, {"op": "shot", "label": "hub"}]
jid, st, res = client.interact(exe, frames, out, steps, renderer=renderer, lease_seconds=60)
print(jid, st.get("state"), json.dumps({k: res.get(k) for k in ("ok", "error", "screen", "capture_exit")}, indent=1))
