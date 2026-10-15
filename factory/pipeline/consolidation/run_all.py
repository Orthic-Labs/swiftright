#!/usr/bin/env python3
"""SR1 consolidation driver: every case on ONE stage through the minimised Sandbox.
python3 run_all.py <stage> [--only substring] ; resumable (skips (case,N) already in results.jsonl for the stage)."""
import json, subprocess, sys, time, re
from pathlib import Path
HERE = Path(__file__).resolve().parent; PIPE = HERE.parent
RENDERER = r"D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll"
P = "pilot-delivery-five-v1/"
R12 = [  # (block label, case dir, N)
 *[(b, c) for b, c in [
  ("5 custom-layout", P+"stack-layout/custom-layout-host-v2/light-centered-execution-v4"),
  ("5 custom-layout", P+"stack-layout/custom-layout-host-v2/rtl-original-execution-v1"),
  *[("1 rounded-rect", P+"text-shape-image/rounded-stroke-host-v1/"+c) for c in ["continuous-geometry-delivery-v2","gen-small-r4-s1","gen-large-r40-s8","gen-wide-r12-s3","gen-frac-r6-s2-45x25"]],
  ("3 stack-overlay", P+"stack-layout/stack-overlay-centered-execution-v9"),
  ("4 text-bundled", P+"text-shape-image/bundled-font-readiness-v6-line-limit-host"),
  *[("2 image", P+"text-shape-image/image-system-star-fill-"+c) for c in ["v10","gen-16pt","gen-120x60","gen-48pt"]],
  *[("9 padding-frame", "blocks-6-10/padding-frame/"+c) for c in ["padding-edges-v1","frame-alignment-v1","frame-alignment-rtl-v1","flexible-frame-v1","nested-fractional-v1"]],
  *[("6 scroll-view", "blocks-6-10/scroll-view/"+c) for c in ["vertical-offset0-v1","vertical-bottom-anchor-v1","horizontal-axis-v1","vertical-text-rows-v1"]],
  *[("10 preference-key", "blocks-6-10/preference-key/"+c) for c in ["reduce-max-sum-v1","nil-default-first-wins-v1"]],
  *[("7 toggle", "blocks-6-10/swiftui.toggle/"+c) for c in ["switch-on-v1","switch-off-v1","switch-labelled-on-v1","checkbox-on-v1","checkbox-off-v1","checkbox-labelled-on-v1"]],
  *[("8 disabled (+button, text colour)", "blocks-6-10/swiftui.disabled/"+c) for c in ["toggle-on-disabled-v1","toggle-off-disabled-v1","checkbox-on-disabled-v1","checkbox-off-disabled-v1","plain-disabled-v1","plain-enabled-v1","button-enabled-v1","button-disabled-v1"]],
  ("8 disabled (+button, text colour)", "blocks-6-10/swiftui.text/foreground-colour-v1"),
  *[("pixel-ties", "blocks-6-10/pixel-ties/"+c) for c in ["ruler-v1","centered-origin-v1","layout-v1"]],
 ]]]
def ls(block, d, label):
    return [(label, f"{block}/{d.name}/{c.name}") for d in sorted((PIPE/block).glob(d)) for c in sorted(d.iterdir()) if (c/"mac-source").is_dir()]
R3 = []
b610 = PIPE/"blocks-6-10"
for lab, g in [("12 binding","swiftui.binding"),("13 textfield","swiftui.textfield"),("14 focus-state","swiftui.focus-state"),("15 ime-marked-text","swiftui.ime-marked-text"),("18 animation","swiftui.animation"),("19 opacity-transition","swiftui.opacity-transition")]:
    R3 += [(lab, f"blocks-6-10/{g}/{c.name}") for c in sorted((b610/g).iterdir()) if (c/"mac-source").is_dir()]
for lab, blk, g in [("11 button","blocks-11-16","swiftui.button"),("16 list","blocks-11-16","swiftui.list"),("17 alert","blocks-17-20","swiftui.alert"),("20 color-scheme","blocks-17-20","swiftui.color-scheme")]:
    R3 += [(lab, f"{blk}/{g}/{c.name}") for c in sorted((PIPE/blk/g).iterdir()) if (c/"mac-source").is_dir()]
JOBS = [(l, c, 20) for l, c in R3] + [(l, c, 3) for l, c in R12]

def main():
    sys.path.insert(0, str(PIPE.parent / "tools")); import cache_paths; cache_paths.preflight("consolidation run_all (pair.py Mac builds)")   # warns < 40 GB internal free, refuses < 15 GB
    stage = sys.argv[1]; only = sys.argv[sys.argv.index("--only")+1] if "--only" in sys.argv else None
    res = HERE/"results.jsonl"
    done = set()
    if res.exists():
        for l in res.read_text().splitlines():
            j = json.loads(l)
            if j["stage"] == stage and j.get("done"): done.add((j["case"], j["n"]))
    for label, case, n in JOBS:
        if (case, n) in done or (only and only not in case): continue
        t = time.time()
        r = subprocess.run([sys.executable, str(PIPE.parent/"tools/pair.py"), str(PIPE/case), "--runs", str(n), "--stage", stage, "--renderer", RENDERER, "--sandbox"], capture_output=True, text=True)
        out = r.stdout + r.stderr
        m = re.search(r"out=(\S+)", out)
        rec = {"stage": stage, "block": label, "case": case, "n": n, "exit": r.returncode, "out": m.group(1) if m else None, "secs": round(time.time()-t), "tail": [l for l in out.splitlines() if "Deprecat" not in l and "return [" not in l and not re.match(r"\s+(semantic run|clock run|run) ", l)][-8:], "done": m is not None}
        with res.open("a") as f: f.write(json.dumps(rec) + "\n")
        print(label, case, n, "exit", r.returncode, rec["secs"], "s", flush=True)
main()
