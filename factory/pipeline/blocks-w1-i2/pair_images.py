#!/usr/bin/env python3
"""Many I2 cases, ONE Windows build. factory/tools/pair.py builds every case in its own package, which compiles the whole product (SwiftRightHost, 40k lines) for each case (367 s each);
the I2 pages are ~25 cases of one product, so this runner puts every case's witness in its own executable target of ONE package, builds that package once with the pair.py tools
(prep.ps1, build.ps1), then for each case captures the Windows exe in the Sandbox (client.capture, as pair.py --sandbox) and the Mac ImageRenderer host (pair.mac), and writes the same
runs/<ts>/{windows,mac}/ layout, build.json (stage and renderer identity) and mac scale guard that pair.py writes. The resample gate is then run on each (pair_resample_report.py).
usage: pair_images.py <stage> <group: cal|gate> [--n N] [--cases a,b] [--tag T] [--no-gate] [--skip-mac]
Nothing here changes pair.py or the shared hosts. The Sandbox is the shared one: capture jobs queue through the client; it is never reset."""
import argparse, json, subprocess, sys, time, zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO / "factory/tools"))
import pair as P   # noqa: E402  (importing pair.py is safe: its main() runs only under __main__)

GROUPS = {"cal": "swiftui.image-calibration", "gate": "swiftui.image-layout"}


def target(case):
    return "I2_" + case.replace("-", "_")


def build_zip(cases, group, stage, zp):
    names = []
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        deps = ",\n    ".join(f'.executableTarget(name: "{target(c)}", dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime"), .product(name: "SwiftRightHost", package: "SwiftRightHost")])' for c in cases)
        stage_dir = rf"{P.STAGE_ROOT}\{stage}".replace("\\", "\\\\")
        z.writestr("Package.swift", f'''// swift-tools-version:6.0
import PackageDescription
// Wave 1 block I2: one executable target per case, ONE product build (factory/pipeline/blocks-w1-i2/pair_images.py).
let package = Package(name: "FactoryProbe", dependencies: [
    .package(name: "fresh-runtime", path: "{stage_dir}\\\\probes\\\\sr0-s\\\\fresh-runtime"),
    .package(path: "{stage_dir}\\\\packages\\\\SwiftRightHost")
], targets: [
    {deps}
], swiftLanguageModes: [.v5])
''')
        for c in cases:
            src = HERE / GROUPS[group] / c / "package/Sources/FactoryProbe"
            for f in sorted(src.iterdir()):
                z.write(f, f"Sources/{target(c)}/{f.name}")
            names.append(target(c))
    return names


def windows_build(cases, group, stage, tag, renderer, reuse=False):
    wroot = P.WIN_ROOT
    host = rf"{wroot}\hosts\i2-{tag}"; tools = rf"{wroot}\pair-tools"; pkg = rf"{host}\package"; ts = time.strftime("%Y%m%d-%H%M%S")
    if reuse:     # the package of an earlier run of this tag is still built on the Dell: capture only
        return {c: rf"{pkg}\scratch\x86_64-unknown-windows-msvc\release\{target(c)}.exe" for c in cases}, rf"{P.STAGE_ROOT}\{stage}"
    P.win(f'powershell -NoProfile -Command "New-Item -ItemType Directory -Force {tools},{host} | Out-Null"')
    P.sh(["scp", "-q", *map(str, P.TOOLS.glob("*.ps1")), f"win:{tools.replace(chr(92), '/')}/"])
    zp = Path.home() / "Library/Caches/SwiftRightFactory" / f"i2-{tag}-{ts}.zip"
    zp.parent.mkdir(parents=True, exist_ok=True)
    build_zip(cases, group, stage, zp)
    wzip = rf"{host}\package-{ts}.zip"
    P.sh(["scp", "-q", str(zp), f"win:{wzip.replace(chr(92), '/')}"])
    zp.unlink()
    stage_dir = rf"{P.STAGE_ROOT}\{stage}"
    P.win(f"powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\prep.ps1 -Zip {wzip} -Pkg {pkg} -Tag {ts} -Stage {stage_dir} -Renderer {renderer}")
    t = time.time()
    r = P.win(f"powershell -NoProfile -ExecutionPolicy Bypass -File {tools}\\build.ps1 -Pkg {pkg}", check=False)
    log = HERE / f".build-{tag}.log"
    P.sh(["scp", "-q", f"win:{pkg.replace(chr(92), '/')}/build.log", str(log)], check=False)
    text = log.read_bytes().decode("utf-16", errors="ignore") if log.read_bytes()[:2] in (b"\xff\xfe", b"\xfe\xff") else log.read_text(errors="replace")
    # build.ps1 exits 99 when FactoryProbe.exe is absent: this package has one executable target per case instead, so "Build complete!" in the build log is the success signal (the wrapper then exits 1 or 99 because of swift's stderr warning)
    if "Build complete!" not in text:
        sys.exit(f"Windows build failed ({r.returncode}); see {log}")
    print(f"windows build ok {time.time() - t:.0f}s ({len(cases)} targets, one product build)", flush=True)
    return {c: rf"{pkg}\scratch\x86_64-unknown-windows-msvc\release\{target(c)}.exe" for c in cases}, stage_dir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage"); ap.add_argument("group", choices=list(GROUPS)); ap.add_argument("--n", type=int, default=3); ap.add_argument("--cases"); ap.add_argument("--tag", default=None)
    ap.add_argument("--no-gate", action="store_true"); ap.add_argument("--skip-mac", action="store_true"); ap.add_argument("--reuse-build", action="store_true"); ap.add_argument("--renderer", default=P.DEFAULT_RENDERER)
    a = ap.parse_args()
    allc = sorted(p.name for p in (HERE / GROUPS[a.group]).iterdir() if (p / "layout.json").is_file())
    cases = [c for c in allc if not a.cases or c in a.cases.split(",")]
    tag = a.tag or f"{a.group}-{a.stage[-8:]}"
    exes, stage_dir = windows_build(cases, a.group, a.stage, tag, a.renderer, a.reuse_build)
    sys.path.insert(0, str(REPO / "factory/tools/sandbox"))
    import client as sbx
    sbx.sync_capture_tool(P.TOOLS)
    results = []
    for c in cases:
        case = HERE / GROUPS[a.group] / c
        out = case / "runs" / time.strftime("%Y%m%d-%H%M%S"); wdir = out / "windows"; wdir.mkdir(parents=True, exist_ok=True)
        P.write_build_info(out, case, a.stage, stage_dir, a.renderer)
        t = time.time()
        jid, st, res = sbx.capture(exes[c], a.n, wdir, renderer=a.renderer)
        (out / "windows-session.log").write_text(json.dumps(dict(job=jid, status=st, result=res), indent=1))
        ok_cap = st.get("state") == "done" and "done" in res
        bad = []
        if ok_cap:
            done = json.loads((wdir / "done.json").read_text(encoding="utf-8-sig")); bad = [d for d in done if d["status"] != "ok"]
        print(f"{c}: windows capture {'ok' if ok_cap and not bad else 'FAILED'} N={a.n} {time.time() - t:.0f}s", flush=True)
        rec = dict(case=f"{GROUPS[a.group].replace('swiftui.image-', '')}/{c}", n=a.n, stage=a.stage, kind=a.group, tag=tag, out=str(out), windowsCapture=bool(ok_cap and not bad), utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        if ok_cap and not a.skip_mac:
            rec["macScaleGuard"] = bool(P.mac(case, case.name, a.n, out))
        if ok_cap and not a.no_gate:
            g = subprocess.run([sys.executable, str(REPO / "factory/tools/pair_resample_report.py"), str(case), str(out)] + (["--calibrate"] if a.group == "cal" else []), capture_output=True, text=True)
            rec["gateExit"] = g.returncode; rec["gateTail"] = g.stdout.strip().splitlines()[-2:]
            rp = out / "resample-report.json"
            if rp.is_file():
                rep = json.loads(rp.read_text()); rec["perLevel"] = rep.get("perLevel"); rec["pairs"] = len(rep["rows"]); rec["pairsPassing"] = sum(1 for r in rep["rows"] if r["ok"])
            print("   ", rec.get("gateTail"), flush=True)
        results.append(rec)
        with (HERE / "results.jsonl").open("a") as f: f.write(json.dumps(rec) + "\n")
    print(json.dumps([{k: r.get(k) for k in ("case", "n", "windowsCapture", "gateExit", "pairsPassing", "pairs")} for r in results], indent=0))


if __name__ == "__main__":
    main()
