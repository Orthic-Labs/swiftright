#!/usr/bin/env python3
"""Stages the product at <ref> on the Dell with ONE deliberately wrong image resampler, for the I2 negative controls (docs/foundations-images-fonts.md 1.4 item 4):
  usage: stage_control.py <nearest-high|straight-alpha|translate-1px|swap-rb> [--ref HEAD]
The product tree is `git archive <ref>` (as factory/tools/stage-product.py) with a text patch applied to ONE file in the staged copy; the repository and the product never carry a control or a flag
(RightKit rule: no QA/dev-control code in a release build). The stage name ends in -i2ctl-<control>; STAGE.json records the control and the patched file's sha256. Run the gate case against it:
  python3 factory/tools/pair.py <gate case> --runs 3 --stage <name> --sandbox ; python3 factory/tools/pair_resample_report.py <case> <run dir>   (must exit 1)"""
import hashlib, importlib.util, json, subprocess, sys, time, zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("stage_product", REPO / "factory/tools/stage-product.py")
sp = importlib.util.module_from_spec(spec); spec.loader.exec_module(sp)
RESAMPLER = "packages/SwiftRightHost/Sources/SwiftRightHost/ImageResampler.swift"
PAINTER = "packages/SwiftRightHost/Sources/SwiftRightHost/ResolvedNodePainter.swift"


def rep(text, old, new):
    assert text.count(old) == 1, f"patch anchor not found exactly once: {old!r}"
    return text.replace(old, new)


def nearest_high(files):
    """nearest-neighbour where `.high` is asked."""
    t = files[RESAMPLER].decode()
    t = rep(t, "case .high?: return Plan(filter: .cubic(b: highCubic.b, c: highCubic.c), mip: true)", "case .high?: return Plan(filter: .nearest, mip: false)")
    files[RESAMPLER] = t.encode()
    return RESAMPLER


def straight_alpha(files):
    """a straight-alpha (non-premultiplied) resample: colour is filtered without its alpha weight and a transparent pixel keeps its colour (dark/odd fringe on alpha edges)."""
    t = files[RESAMPLER].decode()
    t = rep(t, "p[i * 4] = Float(image.rgba[i * 4]) / 255 * a; p[i * 4 + 1] = Float(image.rgba[i * 4 + 1]) / 255 * a", "p[i * 4] = Float(image.rgba[i * 4]) / 255; p[i * 4 + 1] = Float(image.rgba[i * 4 + 1]) / 255")
    t = rep(t, "p[i * 4 + 2] = Float(image.rgba[i * 4 + 2]) / 255 * a; p[i * 4 + 3] = a", "p[i * 4 + 2] = Float(image.rgba[i * 4 + 2]) / 255; p[i * 4 + 3] = a")
    t = rep(t, "guard a > 1e-6 else { continue }\n", "")
    t = rep(t, "bytes[i * 4] = byte(p[i * 4] / a); bytes[i * 4 + 1] = byte(p[i * 4 + 1] / a); bytes[i * 4 + 2] = byte(p[i * 4 + 2] / a); bytes[i * 4 + 3] = byte(a)",
            "bytes[i * 4] = byte(p[i * 4]); bytes[i * 4 + 1] = byte(p[i * 4 + 1]); bytes[i * 4 + 2] = byte(p[i * 4 + 2]); bytes[i * 4 + 3] = byte(a)")
    files[RESAMPLER] = t.encode()
    return RESAMPLER


def translate_1px(files):
    """the image rect moved one device pixel to the right."""
    t = files[PAINTER].decode()
    t = rep(t, "return .image(handle, Rect(x: bounds.x + imageGuardBand, y: bounds.y + imageGuardBand, w: bounds.w - 2 * imageGuardBand, h: bounds.h - 2 * imageGuardBand))\n    }\n}",
            "return .image(handle, Rect(x: bounds.x + 1 + imageGuardBand, y: bounds.y + imageGuardBand, w: bounds.w - 2 * imageGuardBand, h: bounds.h - 2 * imageGuardBand))\n    }\n}")
    files[PAINTER] = t.encode()
    return PAINTER


def swap_rb(files):
    """red and blue exchanged in every registered pixel."""
    t = files[PAINTER].decode()
    t = rep(t, "            var rgba = source.rgba\n            if key.alpha != 255 {", "            var rgba = source.rgba\n            for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }\n            if key.alpha != 255 {")
    files[PAINTER] = t.encode()
    return PAINTER


CONTROLS = {"nearest-high": nearest_high, "straight-alpha": straight_alpha, "translate-1px": translate_1px, "swap-rb": swap_rb}


def main():
    ctl = sys.argv[1]; ref = sys.argv[sys.argv.index("--ref") + 1] if "--ref" in sys.argv else "HEAD"
    commit = sp.git("rev-parse", ref).decode().strip()
    files = sp.files_from_git(commit)
    patched = CONTROLS[ctl](files)
    h = hashlib.sha256()
    for n in sorted(files): h.update(n.encode() + b"\0" + hashlib.sha256(files[n]).digest())
    tree = h.hexdigest()
    name = f"{commit[:9]}-{tree[:8]}-i2ctl-{ctl}"
    meta = dict(name=name, commit=commit, ref=ref, mode="git-archive+i2-control", dirty=False, control=ctl, patchedFile=patched, patchedSha256=hashlib.sha256(files[patched]).hexdigest(),
                treeSha256="sha256:" + tree, files=len(files), paths=sp.PATHS, stagedUtc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    dest = rf"{sp.WIN_STAGE}\{name}"
    probe = subprocess.run(sp.SSH + [f'if (Test-Path {dest}\\STAGE.json) {{ "present" }} else {{ "absent" }}'], capture_output=True, text=True)
    if probe.stdout.strip().endswith("present"):
        print(f"stage {name} already staged"); print(name); return
    zp = REPO / f".stage-{name}.zip"
    try:
        with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
            for n in sorted(files): z.writestr(n, files[n])
            z.writestr("STAGE.json", json.dumps(meta, indent=1))
        subprocess.run(sp.SSH + [f'New-Item -ItemType Directory -Force {sp.WIN_STAGE} | Out-Null'], check=True)
        subprocess.run(["scp", "-q", str(zp), f"win:{sp.WIN_STAGE.replace(chr(92), '/')}/{name}.zip"], check=True)
        r = subprocess.run(sp.SSH + [f'$ErrorActionPreference="Stop"; Expand-Archive {sp.WIN_STAGE}\\{name}.zip {dest}; Move-Item {sp.WIN_STAGE}\\{name}.zip D:\\Claude\\swiftright\\.work\\{name}-stage.zip -Force; "ok"'], capture_output=True, text=True)
        if "ok" not in r.stdout: sys.exit(f"stage extract failed: {r.stdout}{r.stderr}")
    finally:
        zp.unlink(missing_ok=True)
    print(f"staged {name} ({ctl}: {patched})"); print(name)


if __name__ == "__main__":
    main()
