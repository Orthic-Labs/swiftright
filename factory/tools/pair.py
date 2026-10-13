#!/usr/bin/env python3
"""Paired Mac/Windows capture + exact-RGB compare.  python3 pair.py <case-dir> --runs N --stage <name> [--renderer <dll>] [--sandbox]
<case-dir>/package (Windows SwiftPM host, product FactoryProbe) and <case-dir>/mac-source (Mac host sources).
--stage names the ONE product tree every case builds against (factory/tools/stage-product.py: runtime + bridge + SwiftRightHost from a single
commit); the package's @@PRODUCT_STAGE@@ token is replaced with it at zip time. --renderer is the DLL the host loads (default: the 0.7 baseline),
passed to the host per run through SWIFTRIGHT_RENDER_DLL, so the pinned renderer under inputs\renderer is never overwritten or required.
Output: <case-dir>/runs/<ts>/{windows,mac}/*.png, report.json, build.json (stage + renderer identity), diff-NN.png, *.log"""
import argparse, json, re, shutil, subprocess, sys, time, zipfile, io
from pathlib import Path
from PIL import Image, ImageChops

TOOLS = Path(__file__).resolve().parent / "pair"
WIN_ROOT = r"D:\Claude\swiftright\.factory-work"
SSH = ["ssh", "-o", "BatchMode=yes", "win"]
EXE_REL = r"scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe"
STAGE_ROOT = rf"{WIN_ROOT}\product-stage"
DEFAULT_RENDERER = rf"{WIN_ROOT}\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll"


def sh(cmd, log=None, check=True, timeout=None):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if log:
        Path(log).write_text(f"$ {' '.join(map(str, cmd))}\n--stdout--\n{r.stdout}\n--stderr--\n{r.stderr}\nexit={r.returncode}\n")
    if check and r.returncode:
        sys.exit(f"FAILED ({r.returncode}): {' '.join(map(str, cmd))[:200]}\n{(r.stdout + r.stderr)[-1500:]}")
    return r


def win(ps, **kw):
    return sh(SSH + [ps], **kw)


def windows(case, name, runs, out, shared=False, sandbox=False, stage=None, renderer=DEFAULT_RENDERER, steps=None):
    wdir = out / "windows"; wdir.mkdir(parents=True, exist_ok=True)
    host = rf"{WIN_ROOT}\hosts\{name}"; tools = rf"{WIN_ROOT}\pair-tools"
    pkg = rf"{host}\package"; exe = rf"{pkg}\{EXE_REL}"; ts = out.name
    # tools + package zip
    win(f'powershell -NoProfile -Command "New-Item -ItemType Directory -Force {tools},{host} | Out-Null"')
    sh(["scp", "-q", *map(str, TOOLS.glob("*.ps1")), f"win:{tools.replace(chr(92), '/')}/"])
    zp = out / "package.zip"
    stage_dir = rf"{STAGE_ROOT}\{stage}"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted((case / "package").rglob("*")):
            if f.is_file() and "scratch" not in f.relative_to(case / "package").parts:
                if f.name == "Package.swift":
                    z.writestr(f.relative_to(case / "package").as_posix(), f.read_text().replace("@@PRODUCT_STAGE@@", stage_dir.replace("\\", "\\\\")))
                else:
                    z.write(f, f.relative_to(case / "package").as_posix())
    wzip = rf"{host}\package-{ts}.zip"
    sh(["scp", "-q", str(zp), f"win:{wzip.replace(chr(92), '/')}"])
    zp.unlink()
    win(f"powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\prep.ps1 -Zip {wzip} -Pkg {pkg} -Tag {ts} -Stage {stage_dir} -Renderer {renderer}", log=out / "windows-extract.log")
    write_build_info(out, case, stage, stage_dir, renderer)
    t = time.time()
    r = win(f'powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\build.ps1 -Pkg {pkg}', log=out / "windows-build.log", check=False)
    sh(["scp", "-q", f"win:{pkg.replace(chr(92), '/')}/build.log", str(out / "windows-swift-build.log")], check=False)
    if r.returncode:
        sys.exit(f"Windows build failed ({r.returncode}); see {out}/windows-swift-build.log")
    print(f"windows build ok {time.time() - t:.0f}s", flush=True)
    if sandbox:
        # capture inside the long-lived minimised Windows Sandbox (factory/tools/sandbox): no window on the Dell desktop; the host-built exe is read through the mapped folder
        sys.path.insert(0, str(Path(__file__).resolve().parent / "sandbox"))
        import client as sbx
        sbx.sync_capture_tool(TOOLS)
        if steps is not None:
            # F2: interaction job (key/char/click/ime/invoke steps, then a UIA dump of every window the host owns + PrintWindow); lands uia-NN.json beside native-NN.png
            jid, st, res = sbx.interact(exe, runs, wdir, steps, renderer=renderer)
        else:
            jid, st, res = sbx.capture(exe, runs, wdir, renderer=renderer)
        (out / "windows-session.log").write_text(json.dumps(dict(job=jid, status=st, result=res), indent=1))
        if st.get("state") != "done" or "done" not in res:
            sys.exit(f"Sandbox capture failed ({st.get('state')}): {res.get('error')}; see {out}/windows-session.log")
        done = json.loads((wdir / "done.json").read_text(encoding="utf-8-sig"))
        bad = [d for d in done if d["status"] != "ok"]
        print(f"windows capture (sandbox: {'; '.join(res.get('video') or [])}) {len(done) - len(bad)}/{runs} ok" + (f" first error: {bad[0]}" if bad else ""), flush=True)
        return
    # capture (session.ps1 owns the lock and always writes 'free')
    wout = rf"{host}\captures\{ts}"
    r = win(f'powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\session.ps1 -Exe {exe} -Out {wout} -Runs {runs}' + (f' -Shared -Case {name}' if shared else ''),
            log=out / "windows-session.log", check=False, timeout=runs * 90 + 2400)
    sh(["scp", "-q", "-r", f"win:{wout.replace(chr(92), '/')}/*", str(wdir)], check=False)
    if r.returncode:
        sys.exit(f"Windows capture failed ({r.returncode}); see {out}/windows-session.log")
    done = json.loads((wdir / "done.json").read_text(encoding="utf-8-sig"))
    bad = [d for d in done if d["status"] != "ok"]
    print(f"windows capture {len(done) - len(bad)}/{runs} ok" + (f" first error: {bad[0]}" if bad else ""), flush=True)


def write_build_info(out, case, stage, stage_dir, renderer):
    """Identity of what was built and captured: the staged product (commit, tree hash, dirty) and the renderer DLL (sha256)."""
    r = win(f'Get-Content {stage_dir}\\STAGE.json -Raw; "---"; (Get-FileHash {renderer} -Algorithm SHA256).Hash.ToLower()')
    meta_txt, _, sha = r.stdout.partition("---")
    meta = json.loads(meta_txt)
    info = dict(stage=meta, renderer=dict(path=renderer, sha256=sha.strip()), case=str(case))
    (out / "build.json").write_text(json.dumps(info, indent=1))
    print(f"build: stage {meta['name']} ({meta['mode']}{', DIRTY' if meta.get('dirty') else ''}) renderer sha256 {sha.strip()[:12]}", flush=True)


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


def load_steps(case, cli):
    """Interaction steps: --steps <file.json> (a list, or {"steps":[..]}) or <case>/pair.json {"steps":[..]}; None = plain capture. Step vocabulary: factory/tools/sandbox/guest/job-interact.ps1."""
    if cli:
        v = json.loads(Path(cli).read_text())
        return v["steps"] if isinstance(v, dict) else v
    pj = case / "pair.json"
    if pj.is_file():
        return json.loads(pj.read_text()).get("steps")
    return None


def ink_bbox(img, rect):
    """bbox (capture px) of pixels inside rect whose colour is not one of the 3 dominant frame colours (background and flat fills): glyph/AA ink."""
    flat = {c for _, c in sorted(img.getcolors(1 << 20), reverse=True)[:3]}
    pts = [(x, y) for y in range(rect[1], rect[3]) for x in range(rect[0], rect[2]) if img.getpixel((x, y)) not in flat]
    return None if not pts else (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts) + 1, max(p[1] for p in pts) + 1)


def npx(d):
    w, h = d.size
    return w * h - ImageChops.lighter(ImageChops.lighter(*d.split()[:2]), d.split()[2]).histogram()[0]


def edge_band(im):
    """L mask (255 = in band): pixels within 1 px of an edge in the Mac image (3x3 neighbourhood not uniform in any channel, dilated by 1; sr1-decisions #5)."""
    from PIL import ImageFilter
    e = None
    for c in im.split():
        m = ImageChops.difference(c.filter(ImageFilter.MaxFilter(3)), c.filter(ImageFilter.MinFilter(3)))
        e = m if e is None else ImageChops.lighter(e, m)
    return e.point(lambda v: 255 if v else 0).filter(ImageFilter.MaxFilter(3))


def edge_gate(im, iw, exclusions=()):
    """Verdict exact | edge-aa<=32 | fail, with counts (exact = no difference outside the excluded rects; compare() relabels that exact-with-exclusions when an excluded region differs). Pixels in excluded rects are ignored."""
    a, b, c = ImageChops.difference(im, iw).split()
    d = ImageChops.lighter(ImageChops.lighter(a, b), c)
    for e in exclusions:
        d.paste(0, e["rect"])
    band = edge_band(im)
    black = Image.new("L", d.size, 0)
    inb, outb = Image.composite(d, black, band), Image.composite(black, d, band)
    cnt = lambda x: x.size[0] * x.size[1] - x.histogram()[0]
    ti, to = cnt(inb), cnt(outb); mi, mo = inb.getextrema()[1], outb.getextrema()[1]
    verdict = "exact" if ti + to == 0 else ("edge-aa<=32" if to == 0 and mi <= 32 else "fail")
    return dict(verdict=verdict, totalDiff=ti + to, inBandDiff=ti, outOfBandDiff=to, maxInBand=mi, maxOutOfBand=mo,
                bandPixels=cnt(band))


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
        g = edge_gate(im, iw, exclusions)
        full_px = npx(full)
        # "exact" means pixel-identical over the whole frame. Identical outside named excluded regions while the regions differ is
        # reported as exact-with-exclusions (never as exact); the regions are named in every report line and in report.json.
        verdict = g["verdict"]
        if exclusions and verdict == "exact" and full_px > 0:
            verdict = "exact-with-exclusions"
        row = dict(run=i, verdict=verdict, gate=g, exact=full_px == 0, differentPixels=npx(gated), maxdiff=max(max(e) for e in gated.getextrema()), diffbbox=bbox)
        if exclusions:
            row["fullFrameDifferentPixels"] = full_px
            row["excluded"] = []
            for e in exclusions:
                r = e["rect"]
                row["excluded"].append(dict(name=e["name"], rect=list(r), diffPixels=npx(full.crop(r)) , macInkBBox=ink_bbox(im, r), winInkBBox=ink_bbox(iw, r)))
        rows.append(row)
        if bbox and first is None:
            first = i; ImageChops.invert(gated).save(out / f"diff-{i:02d}.png")
    passing = ("exact", "exact-with-exclusions", "edge-aa<=32")
    ok = [r for r in rows if r.get("verdict") in passing]
    bad = [r for r in rows if r.get("verdict") not in passing]
    nex = sum(1 for r in rows if r.get("verdict") == "exact")
    nexw = sum(1 for r in rows if r.get("verdict") == "exact-with-exclusions")
    worst = max((r.get("maxdiff", 0) for r in rows), default=0)
    bbox = next((r.get("diffbbox") for r in bad if r.get("diffbbox")), None)
    rep = dict(pairs=runs, exact=nex, exactWithExclusions=nexw, edgeAA=len(ok) - nex - nexw, fail=len(bad), maxdiff=worst, diffbbox=bbox, rows=rows)
    if (out / "build.json").is_file():
        rep["build"] = json.loads((out / "build.json").read_text())
    if exclusions:
        rep["gate"] = "exact outside excluded regions"
        rep["excludedRegions"] = [dict(name=e["name"], rect=list(e["rect"])) for e in exclusions]
    (out / "report.json").write_text(json.dumps(rep, indent=1))
    for r in rows:
        if "gate" in r:
            g = r["gate"]; print(f"  run {r['run']:02d} {r['verdict']} total={g['totalDiff']} in-band={g['inBandDiff']} out-of-band={g['outOfBandDiff']} max-in-band={g['maxInBand']} max-out-of-band={g['maxOutOfBand']}")
    names = ", ".join(e["name"] + str(list(e["rect"])) for e in exclusions)
    print(f"pairs={runs} exact={nex} exact-with-exclusions={nexw}" + (f" (excluding: {names})" if exclusions else "") + f" edge-aa<=32={len(ok) - nex - nexw} fail={len(bad)} maxdiff={worst} diffbbox={bbox}")
    return len(ok) == runs


def semantic_gate(case, out):
    """Cases whose pair.json declares a semantic gate (imageFrame: Image(systemName:) frame/ink/tint; textGate: glyph-region ink bbox) run its report tool.
    Returns None when the case declares none, else whether the semantic gate passed."""
    pj = case / "pair.json"
    if not pj.is_file():
        return None
    cfg = json.loads(pj.read_text())
    tool = "pair_image_report.py" if "imageFrame" in cfg else "pair_control_report.py" if "controlGate" in cfg else "pair_text_report.py" if "textGate" in cfg else None
    if not tool:
        return None
    r = subprocess.run([sys.executable, str(Path(__file__).resolve().parent / tool), str(case), str(out)], capture_output=True, text=True)
    print(r.stdout + r.stderr, end="")
    return r.returncode == 0


def semantic_decides(case):
    """Cases whose pixels differ by design inside regions the exclusions cannot name (Image(systemName:) glyphs; a labelled control whose x follows the label's width): the semantic gate alone decides."""
    cfg = json.loads((case / "pair.json").read_text())
    return "imageFrame" in cfg or "controlGate" in cfg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case"); ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--stage", help="name of the staged product tree (factory/tools/stage-product.py prints it); required for Windows builds")
    ap.add_argument("--renderer", default=DEFAULT_RENDERER, help="renderer DLL (Windows path) the host loads, per run via SWIFTRIGHT_RENDER_DLL (--sandbox only)")
    ap.add_argument("--shared", action="store_true", help="PrintWindow capture without the exclusive desktop lock (background, no activation, no input); default unchanged"); ap.add_argument("--sandbox", action="store_true", help="run the Windows capture inside the long-lived minimised Windows Sandbox (factory/tools/sandbox); the build still runs on the Dell host over SSH; default unchanged"); ap.add_argument("--skip-mac", action="store_true"); ap.add_argument("--skip-windows", action="store_true")
    ap.add_argument("--exclude-text-bbox", action="append", metavar="X0,Y0,X1,Y1", help="named-in-report text region excluded from the pixel gate (repeatable); also <case>/pair.json excludeRects")
    ap.add_argument("--steps", metavar="FILE.json", help="F2: interaction steps for the Sandbox run (key/char/click/ime/invoke/wait/dump/shot); default: <case>/pair.json \"steps\" if present")
    ap.add_argument("--recompare", metavar="RUN_DIR", help="re-evaluate an existing runs/<ts> dir with the gate, no capture")
    ap.add_argument("--out", help="reuse an existing runs/<ts> dir for the skipped side")
    a = ap.parse_args()
    case = Path(a.case).resolve(); name = case.name
    if a.recompare:
        out = Path(a.recompare).resolve(); n = len(list((out / "mac").glob("run-*.png")))
        ok = compare(out, n, load_exclusions(case, a.exclude_text_bbox))
        sem = semantic_gate(case, out)
        sys.exit(0 if (ok if sem is None else sem and (ok or semantic_decides(case))) else 1)
    out = Path(a.out) if a.out else case / "runs" / time.strftime("%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    if not a.skip_windows:
        if not a.stage: sys.exit("--stage <name> is required (python3 factory/tools/stage-product.py)")
        if a.renderer != DEFAULT_RENDERER and not a.sandbox: sys.exit("--renderer needs --sandbox (the Dell-desktop session path does not pass it to the host)")
        steps = load_steps(case, a.steps)
        if steps is not None and not a.sandbox: sys.exit("--steps (and pair.json steps) need --sandbox")
        windows(case, name, a.runs, out, a.shared, a.sandbox, a.stage, a.renderer, steps)
    if not a.skip_mac: mac(case, name, a.runs, out)
    print(f"out={out}")
    ok = compare(out, a.runs, load_exclusions(case, a.exclude_text_bbox))
    sem = semantic_gate(case, out)
    if sem is None:
        sys.exit(0 if ok else 1)
    # An Image(systemName:) case differs from the Mac inside the glyph region by design (substitute provider): its semantic gate decides.
    image = semantic_decides(case)
    sys.exit(0 if sem and (ok or image) else 1)


if __name__ == "__main__":
    main()
