#!/usr/bin/env python3
"""usage: render.py <exe path on the Dell (D:\\...)> <frames> <out dir> : ONE Sandbox `interact` job (the shared worker queues it behind other lanes).
Run k (1-based) is frame k-1 = section (k-1)//2, light for odd k, dark for even k (the host numbers its launches with a counter file).
Per run: wait for the hub to load and lay out, then PrintWindow -> native-NN-hub.png; host stdout/stderr in host-NN.*."""
import sys, json
sys.path.insert(0, "/Volumes/D/claude/swiftright/factory/tools/sandbox")
import client
exe, frames, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
steps = [{"op": "wait", "ms": 6000}, {"op": "shot", "label": "hub"}]
jid, st, res = client.interact(exe, frames, out, steps, lease_seconds=60)
print(jid, st.get("state"), json.dumps({k: res.get(k) for k in ("ok", "error", "screen", "capture_exit")}, indent=1))
