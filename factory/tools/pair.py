#!/usr/bin/env python3
"""Paired Mac/Windows capture + exact-RGB compare.  python3 pair.py <case-dir> --runs N [--skip-mac] [--skip-windows]
<case-dir>/package (Windows SwiftPM host, product FactoryProbe) and <case-dir>/mac-source (Mac host sources).
Output: <case-dir>/runs/<ts>/{windows,mac}/*.png, report.json, diff-NN.png, *.log"""
import argparse, json, re, shutil, subprocess, sys, time, zipfile, io
from pathlib import Path
from PIL import Image, ImageChops

TOOLS = Path(__file__).resolve().parent / "pair"
WIN_ROOT = r"D:\Claude\swiftright\.factory-work"
SSH = ["ssh", "-o", "BatchMode=yes", "win"]
EXE_REL = r"scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe"


def sh(cmd, log=None, check=True, timeout=None):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if log:
        Path(log).write_text(f"$ {' '.join(map(str, cmd))}\n--stdout--\n{r.stdout}\n--stderr--\n{r.stderr}\nexit={r.returncode}\n")
    if check and r.returncode:
        sys.exit(f"FAILED ({r.returncode}): {' '.join(map(str, cmd))[:200]}\n{(r.stdout + r.stderr)[-1500:]}")
    return r


def win(ps, **kw):
    return sh(SSH + [ps], **kw)


def windows(case, name, runs, out):
    wdir = out / "windows"; wdir.mkdir(parents=True, exist_ok=True)
    host = rf"{WIN_ROOT}\hosts\{name}"; tools = rf"{WIN_ROOT}\pair-tools"
    pkg = rf"{host}\package"; exe = rf"{pkg}\{EXE_REL}"; ts = out.name
    # tools + package zip
    win(f'powershell -NoProfile -Command "New-Item -ItemType Directory -Force {tools},{host} | Out-Null"')
    sh(["scp", "-q", *map(str, TOOLS.glob("*.ps1")), f"win:{tools.replace(chr(92), '/')}/"])
    zp = out / "package.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted((case / "package").rglob("*")):
            if f.is_file() and "scratch" not in f.relative_to(case / "package").parts:
                z.write(f, f.relative_to(case / "package").as_posix())
    wzip = rf"{host}\package-{ts}.zip"
    sh(["scp", "-q", str(zp), f"win:{wzip.replace(chr(92), '/')}"])
    zp.unlink()
    win(f"powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\prep.ps1 -Zip {wzip} -Pkg {pkg} -Tag {ts}", log=out / "windows-extract.log")
    t = time.time()
    r = win(f'powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\build.ps1 -Pkg {pkg}', log=out / "windows-build.log", check=False)
    sh(["scp", "-q", f"win:{pkg.replace(chr(92), '/')}/build.log", str(out / "windows-swift-build.log")], check=False)
    if r.returncode:
        sys.exit(f"Windows build failed ({r.returncode}); see {out}/windows-swift-build.log")
    print(f"windows build ok {time.time() - t:.0f}s", flush=True)
    # capture (session.ps1 owns the lock and always writes 'free')
    wout = rf"{host}\captures\{ts}"
    r = win(f'powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\session.ps1 -Exe {exe} -Out {wout} -Runs {runs}',
            log=out / "windows-session.log", check=False, timeout=runs * 90 + 2400)
    sh(["scp", "-q", "-r", f"win:{wout.replace(chr(92), '/')}/*", str(wdir)], check=False)
    if r.returncode:
        sys.exit(f"Windows capture failed ({r.returncode}); see {out}/windows-session.log")
    done = json.loads((wdir / "done.json").read_text(encoding="utf-8-sig"))
    bad = [d for d in done if d["status"] != "ok"]
    print(f"windows capture {len(done) - len(bad)}/{runs} ok" + (f" first error: {bad[0]}" if bad else ""), flush=True)


def mac(case, name, runs, out):
    mdir = out / "mac"; mdir.mkdir(parents=True, exist_ok=True)
    cache = Path.home() / "Library/Caches/SwiftRightFactory/pair" / name
    (cache / "mc").mkdir(parents=True, exist_ok=True); (cache / "bin").mkdir(exist_ok=True)
    srcs = sorted(str(p) for p in (case / "mac-source/Sources").rglob("*.swift"))
    sh(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-O", "-module-cache-path", str(cache / "mc"),
        "-o", str(cache / "bin/host"), *srcs], log=out / "mac-build.log")
    # the host only accepts scratch roots under a prefix hard-coded in its source
    m = re.search(r'scratchPrefix\s*=\s*"([^"]+)"', "\n".join(Path(s).read_text() for s in srcs))
    base = Path(m.group(1)) if m else cache / "scratch"
    allsrc = "\n".join(Path(s).read_text() for s in srcs)
    png_mode = 'value("--png")' in allsrc          # older rounded-style host: --plain --scale S --png FILE
    scale_flag = ['"--scale"' in allsrc]
    for i in range(1, runs + 1):
        if png_mode:
            sh([str(cache / "bin/host"), "--plain", "--scale", "2.5", "--png", str(mdir / f"run-{i:02d}.png")],
               log=out / f"mac-run-{i:02d}.log", timeout=120)
            continue
        scratch = base / f"pair-{out.name}-{i:02d}"
        sh([str(cache / "bin/host"), "--observe", *(["--scale", "2.5"] if scale_flag[0] else []), "--scratch-root", str(scratch)],
           log=out / f"mac-run-{i:02d}.log", timeout=120)
        shutil.move(str(scratch / "client.png"), mdir / f"run-{i:02d}.png")
    print(f"mac capture {runs}/{runs} ok", flush=True)


def load_exclusions(case, cli):
    """Named text exclusion rects (px, [x0,y0,x1,y1) in the 800x600 capture). Source: <case>/pair.json {"excludeRects":[{"name":..,"rect":[..]}]} and/or --exclude-text-bbox x0,y0,x1,y1 (repeatable)."""
    ex = []
    pj = case / "pair.json"
    if pj.is_file():
        for e in json.loads(pj.read_text()).get("excludeRects", []):
            ex.append(dict(name=e["name"], rect=tuple(e["rect"])))
    for i, c in enumerate(cli or []):
        ex.append(dict(name=f"cli-text-{i + 1}", rect=tuple(int(v) for v in c.split(","))))
    return ex


def ink_bbox(img, rect):
    """bbox (capture px) of pixels inside rect whose colour is not one of the 3 dominant frame colours (background and flat fills): glyph/AA ink."""
    flat = {c for _, c in sorted(img.getcolors(1 << 20), reverse=True)[:3]}
    pts = [(x, y) for y in range(rect[1], rect[3]) for x in range(rect[0], rect[2]) if img.getpixel((x, y)) not in flat]
    return None if not pts else (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts) + 1, max(p[1] for p in pts) + 1)


def npx(d):
    w, h = d.size
    return w * h - ImageChops.lighter(ImageChops.lighter(*d.split()[:2]), d.split()[2]).histogram()[0]


def compare(out, runs, exclusions=()):
    """exact = pixel-identical outside the named exclusion rects. Excluded regions are reported separately
    (diff pixel count, ink bbox on each side); they never gate. Without exclusions this is the plain full-frame exact diff."""
    rows, first = [], None
    for i in range(1, runs + 1):
        a, b = out / f"mac/run-{i:02d}.png", out / f"windows/native-{i:02d}.png"
        if not (a.is_file() and b.is_file()):
            rows.append(dict(run=i, error="missing capture")); continue
        im, iw = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
        if im.size != iw.size or im.size != (800, 600):
            rows.append(dict(run=i, error=f"size mac={im.size} win={iw.size}")); continue
        full = ImageChops.difference(im, iw)
        gated = full.copy()
        for e in exclusions:
            gated.paste((0, 0, 0), e["rect"])
        bbox = gated.getbbox()
        row = dict(run=i, exact=bbox is None, differentPixels=npx(gated), maxdiff=max(max(e) for e in gated.getextrema()), diffbbox=bbox)
        if exclusions:
            row["fullFrameDifferentPixels"] = npx(full)
            row["excluded"] = []
            for e in exclusions:
                r = e["rect"]
                row["excluded"].append(dict(name=e["name"], rect=list(r), diffPixels=npx(full.crop(r)) , macInkBBox=ink_bbox(im, r), winInkBBox=ink_bbox(iw, r)))
        rows.append(row)
        if bbox and first is None:
            first = i; ImageChops.invert(gated).save(out / f"diff-{i:02d}.png")
    ok = [r for r in rows if r.get("exact")]
    bad = [r for r in rows if not r.get("exact")]
    worst = max((r.get("maxdiff", 0) for r in rows), default=0)
    bbox = next((r.get("diffbbox") for r in bad if r.get("diffbbox")), None)
    rep = dict(pairs=runs, exact=len(ok), maxdiff=worst, diffbbox=bbox, rows=rows)
    if exclusions:
        rep["gate"] = "exact outside excluded regions"
        rep["excludedRegions"] = [dict(name=e["name"], rect=list(e["rect"])) for e in exclusions]
    (out / "report.json").write_text(json.dumps(rep, indent=1))
    print(f"pairs={runs} exact={len(ok)} maxdiff={worst} diffbbox={bbox}" + (f" (gate excludes: {', '.join(e['name'] + str(list(e['rect'])) for e in exclusions)})" if exclusions else ""))
    return len(ok) == runs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case"); ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--skip-mac", action="store_true"); ap.add_argument("--skip-windows", action="store_true")
    ap.add_argument("--exclude-text-bbox", action="append", metavar="X0,Y0,X1,Y1", help="named-in-report text region excluded from the pixel gate (repeatable); also <case>/pair.json excludeRects")
    ap.add_argument("--out", help="reuse an existing runs/<ts> dir for the skipped side")
    a = ap.parse_args()
    case = Path(a.case).resolve(); name = case.name
    out = Path(a.out) if a.out else case / "runs" / time.strftime("%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    if not a.skip_windows: windows(case, name, a.runs, out)
    if not a.skip_mac: mac(case, name, a.runs, out)
    print(f"out={out}")
    sys.exit(0 if compare(out, a.runs, load_exclusions(case, a.exclude_text_bbox)) else 1)


if __name__ == "__main__":
    main()
