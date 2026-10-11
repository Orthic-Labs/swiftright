#!/usr/bin/env python3
"""Verify Mac/Windows/stimulus step identity before any native capture."""
import argparse, hashlib, json
from pathlib import Path

def load(path):
    return json.loads(path.read_text(encoding="utf-8"))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(root, config):
    base = root / "probes" / "sr0-o" / "f1-cross" / "cross" / config
    stimulus_path = base / "stimulus.json"; mac_path = base / "steps-mac.json"; win_path = base / "steps-win.json"
    for path in (stimulus_path, mac_path, win_path):
        if not path.is_file() or path.is_symlink(): raise ValueError(f"missing or unsafe plan: {path}")
    stimulus, mac, win = load(stimulus_path), load(mac_path), load(win_path)
    expected = stimulus.get("steps")
    if not isinstance(expected, list) or not expected: raise ValueError("stimulus steps missing")
    expected_ids = [x.get("id") for x in expected]
    expected_logical = [x.get("logicalAction") for x in expected]
    rows = {"stimulus": stimulus, "mac": mac, "win": win}
    for label, plan in (("mac", mac), ("win", win)):
        steps = plan.get("steps")
        if not isinstance(steps, list) or [x.get("id") for x in steps] != expected_ids:
            raise ValueError(f"{label} step IDs differ from stimulus: config={config}")
        if [x.get("logicalAction") for x in steps] != expected_logical:
            raise ValueError(f"{label} logical actions differ from stimulus: config={config}")
    launch = mac.get("launchArgs", [])
    if not isinstance(launch, list) or "--fixture" not in launch: raise ValueError(f"Mac launch fixture missing: {config}")
    fixture = launch[launch.index("--fixture") + 1] if launch.index("--fixture") + 1 < len(launch) else ""
    expected_fixture = str(stimulus.get("fixtureId", "")).split("-", 1)[0]
    if fixture != expected_fixture: raise ValueError(f"Mac fixture launch mismatch: {config} {fixture} != {expected_fixture}")
    return {"config": config, "stepIds": expected_ids, "logicalActions": expected_logical, "fixture": fixture,
            "stimulusSha256": digest(stimulus_path), "macStepsSha256": digest(mac_path), "winStepsSha256": digest(win_path)}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--root", type=Path, required=True); ap.add_argument("--config", action="append", required=True)
    ns = ap.parse_args(); root = ns.root.resolve(); rows = [verify(root, c) for c in ns.config]
    print(json.dumps({"kind": "sr0-mac-plan-semantic-verification-v1", "configs": rows}, indent=2))

if __name__ == "__main__": main()
