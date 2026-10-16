#!/usr/bin/env python3
"""Make the factory's Windows capture hosts pass the explicit render scale 2.5 through the public API (decision H17).

The hosts used to take their scale from GetDpiForWindow (FactoryViewport.swift), which needs a 240 dpi display. They now ask the renderer
for 2.5 (`Bridge.run(renderScale:)`) and read the scale the renderer reports, so there is ONE scale source and it does not depend on the
display. The host has no scale logic of its own and parses no environment.

Applies exact-text edits to the host templates (`CaptureHost.template.swift`) and to the hosts already stamped from them
(`<case>/package/Sources/FactoryProbe/main.swift`) under factory/pipeline/blocks-*. Idempotent: a file that already passes the scale is
skipped. A file where an edit does not apply exactly is reported and left alone.

  python3 factory/tools/pass_render_scale.py            # apply
  python3 factory/tools/pass_render_scale.py --check    # report only; exit 1 if any host does not pass the scale
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARK = "factoryRenderScale"

EDITS = [
    # (old, new, required)
    ("            scale = metrics.scale\n",
     "            // H17: the scale is the renderer's own report (the explicit render scale passed to run below), never GetDpiForWindow.\n"
     "            scale = abi.scale\n"
     "            let scaleOK = abs(abi.scale - factoryRenderScale) < 1e-4\n"
     "            print(\"HOST_SCALE_GUARD requested=\\(factoryRenderScale) renderer=\\(abi.scale) clientDPI=\\(metrics.dpi) status=\\(scaleOK ? \"PASS\" : \"MISMATCH\")\")\n"
     "            guard scaleOK else { throw NSError(domain: \"HostRenderScaleMismatch\", code: 1) }\n", True),
    ("resolve(dpi: metrics.dpi)", "resolve(dpi: UInt32((scale * 96).rounded()))", False),
    ("owned.size.logicalWidth", "(CGFloat(width) / CGFloat(scale))", False),
    ("owned.size.logicalHeight", "(CGFloat(height) / CGFloat(scale))", False),
    ('try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)',
     'try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240, renderScale: factoryRenderScale)', "run"),
    ('try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240, pointerMoves: true)',
     'try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240, pointerMoves: true, renderScale: factoryRenderScale)', "run"),
    ("let result: Int32 = MainActor.assumeIsolated {",
     "/// The density every gate was fitted at (decision C12 on the Mac). Passed to the renderer as an explicit render scale (decision H17).\n"
     "let factoryRenderScale: Float = 2.5\n\n"
     "let result: Int32 = MainActor.assumeIsolated {", True),
]


def targets():
    for p in sorted((ROOT / "factory/pipeline").glob("blocks-*/**/CaptureHost.template.swift")):
        yield p
    for p in sorted((ROOT / "factory/pipeline").glob("blocks-*/**/package/Sources/FactoryProbe/main.swift")):
        yield p


def main():
    check = "--check" in sys.argv
    done = skipped = bad = 0
    for p in targets():
        s = p.read_text()
        if MARK in s:
            skipped += 1
            continue
        if "scale = metrics.scale" not in s:
            continue   # not a Windows capture host of this family
        new = s
        ok = True
        groups = {}
        for old, rep, required in EDITS:
            hit = old in new
            if hit:
                new = new.replace(old, rep)
            if isinstance(required, str):
                groups[required] = groups.get(required, False) or hit
            elif required and not hit:
                ok = False
        ok = ok and all(groups.values())
        if not ok:
            bad += 1
            print("NOT APPLIED (an edit does not match exactly):", p.relative_to(ROOT))
            continue
        if not check:
            p.write_text(new)
        done += 1
    print(f"{'would change' if check else 'changed'} {done}, already passing {skipped}, not applied {bad}")
    return 1 if (bad or (check and done)) else 0


if __name__ == "__main__":
    sys.exit(main())
