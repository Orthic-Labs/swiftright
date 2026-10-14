#!/usr/bin/env python3
"""Fixture builder for the mutation calibration (README.md). Copies run 01 of one committed or rerun evidence directory per BASE into
factory/pipeline/mutation-calibration/fixtures/<id>/ so the calibration runs offline and byte-stable: no capture, no Windows, no Sandbox.

  python3 fixtures.py            # rebuild every fixture from the SOURCE paths below (read-only on the sources)
Each fixture: pair.json (the case's own gate configuration, unchanged), run/ (run 01 inputs only), SOURCE.json (where it came from)."""
import json, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIPE = ROOT / "factory/pipeline"
OUT = PIPE / "mutation-calibration/fixtures"

# id -> (case dir under factory/pipeline, run dir name, extra run-relative file globs beyond the PNG pair)
B6, B11, B17 = "blocks-6-10", "blocks-11-16", "blocks-17-20"
BASES = {
    # pixel gate (pair.py compare / edge gate / haze / exclusions)
    "px-exact":      (f"{B6}/padding-frame/frame-alignment-v1", "20261014-171910", []),
    "px-edge":       ("pilot-delivery-five-v1/text-shape-image/rounded-stroke-host-v1/continuous-geometry-delivery-v2", "20261014-163619", []),
    "px-fractional": (f"{B6}/padding-frame/nested-fractional-v1", "20261014-173407", []),
    "px-ties":       (f"{B6}/pixel-ties/layout-v1", "20261014-182749", []),
    "px-haze":       (f"{B17}/swiftui.color-scheme/switch-on-dark-v1", "20261014-162645", []),
    "px-excl":       ("pilot-delivery-five-v1/stack-layout/stack-overlay-centered-execution-v9", "20261014-165602", []),
    # text gates
    "text-gate":     ("pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v6-line-limit-host", "20261014-165825", []),
    "tc-red":        (f"{B11}/swiftui.button/borderless-red-v1", "20261014-053614", []),
    "tc-dark":       (f"{B17}/swiftui.color-scheme/text-dark-v1", "20261014-162943", []),
    "tc-fg":         (f"{B6}/swiftui.text/foreground-colour-v1", "20261014-182126", []),
    # control gates
    "btn-bordered":  (f"{B11}/swiftui.button/bordered-v1", "20261014-053055", []),
    "btn-prominent": (f"{B11}/swiftui.button/prominent-v1", "20261014-061108", []),
    "btn-disabled":  (f"{B6}/swiftui.disabled/button-disabled-v1", "20261014-181921", []),
    "ctl-switch":    (f"{B6}/swiftui.toggle/switch-labelled-on-v1", "20261014-175720", []),
    "ctl-checkbox":  (f"{B6}/swiftui.toggle/checkbox-labelled-on-v1", "20261014-180300", []),
    # list gate
    "list-arrow":    (f"{B11}/swiftui.list/arrow-keys-v1", "20261013-224316", ["mac/list-01.json", "windows/uia-01.json"]),
    "list-var":      (f"{B11}/swiftui.list/variable-rows-selected-v1", "20261014-025727", ["mac/list-01.json", "windows/uia-01.json"]),
    # semantic gate
    "sem-click":     (f"{B11}/swiftui.button/click-increments-v1", "20261014-214203", ["mac/ax-01.json", "windows/uia-01.json"]),
    "sem-binding":   (f"{B6}/swiftui.binding/derived-click-v1", "20261014-195505", ["mac/ax-01*.json", "windows/uia-01*.json"]),
    "sem-alert-three": (f"{B17}/swiftui.alert/three-buttons-v1", "20261014-225724", ["mac/ax-01*.json", "windows/uia-01*.json"]),
    "sem-alert-default": (f"{B17}/swiftui.alert/default-enter-v1", "20261014-224807", ["mac/ax-01*.json", "windows/uia-01*.json"]),
    "sem-focus-tab": (f"{B6}/swiftui.focus-state/tab-order-v1", "20261014-203430", ["mac/ax-01*.json", "windows/uia-01*.json", "windows/host-01.stdout.txt", "mac-run-01.log"]),
    "sem-ime":       (f"{B6}/swiftui.ime-marked-text/ime-composing-v1", "20261014-204651", ["mac/ax-01*.json", "windows/uia-01*.json", "windows/host-01.stdout.txt", "mac-run-01.log"]),
    "sem-tf-placeholder": (f"{B6}/swiftui.textfield/placeholder-v1", "20261014-201102", ["mac/ax-01*.json", "windows/uia-01*.json", "mac-run-01.log"]),
    # text origin gate (also semantic)
    "to-filled":     (f"{B6}/swiftui.textfield/filled-truncated-v1", "20261014-200812", ["mac/ax-01*.json", "windows/uia-01*.json", "mac-run-01.log"]),
    "to-caret":      (f"{B6}/swiftui.textfield/caret-empty-v1", "20261014-200431", ["mac/ax-01*.json", "windows/uia-01*.json", "mac-run-01.log"]),
    "to-selected":   (f"{B6}/swiftui.focus-state/programmatic-v1", "20261014-202647", ["mac/ax-01*.json", "windows/uia-01*.json", "mac-run-01.log"]),
    # clock gate
    "clk-linear":    (f"{B6}/swiftui.animation/linear-width-v1", "20261013-224725", ["mac/run-01-f*.png", "windows/native-01-f*.png", "windows/host-01-f*.stdout.txt", "mac-run-01.log"]),
    "clk-spring":    (f"{B6}/swiftui.animation/default-spring-v1", "20261013-232853", ["mac/run-01-f*.png", "windows/native-01-f*.png", "windows/host-01-f*.stdout.txt", "mac-run-01.log"]),
    "clk-move":      (f"{B6}/swiftui.opacity-transition/move-leading-v1", "20261014-003055", ["mac/run-01-f*.png", "windows/native-01-f*.png", "windows/host-01-f*.stdout.txt", "mac-run-01.log"]),
    "clk-fade":      (f"{B6}/swiftui.opacity-transition/insertion-fade-v1", "20261014-002352", ["mac/run-01-f*.png", "windows/native-01-f*.png", "windows/host-01-f*.stdout.txt", "mac-run-01.log"]),
    # image gate
    "img-star":      ("pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v10", "20261013-221400", ["windows/host-01.stdout.txt"]),
}


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    for bid, (case, run, extra) in BASES.items():
        src_case, src_run = PIPE / case, PIPE / case / "runs" / run
        dst = OUT / bid
        if dst.exists():
            shutil.rmtree(dst)
        (dst / "run").mkdir(parents=True)
        pj = src_case / "pair.json"
        if pj.is_file():
            shutil.copy2(pj, dst / "pair.json")
        else:
            (dst / "pair.json").write_text("{}\n")
        clock = any("-f*" in e for e in extra)
        wanted = ([] if clock else ["mac/run-01.png", "windows/native-01.png"]) + extra
        got = []
        for pat in wanted:
            hits = sorted(src_run.glob(pat))
            if not hits and "*" not in pat and not clock and pat in ("mac/run-01.png", "windows/native-01.png"):
                sys.exit(f"{bid}: missing {src_run / pat}")
            for h in hits:
                rel = h.relative_to(src_run)
                (dst / "run" / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(h, dst / "run" / rel)
                got.append(str(rel))
        (dst / "SOURCE.json").write_text(json.dumps(dict(case=case, caseName=src_case.name, run=run, files=sorted(set(got))), indent=1))
        print(bid, len(got), "files")


if __name__ == "__main__":
    build()
