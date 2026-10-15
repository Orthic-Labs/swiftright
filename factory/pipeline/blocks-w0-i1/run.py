#!/usr/bin/env python3
"""Wave 0 block I1 driver (Windows side).  usage: run.py stage|build|decode [--runs N] [--out DIR] [--stage NAME]
  stage    stage the product working tree on the Dell (factory/tools/stage-product.py --working-tree); prints the stage name
  build    zip dump-host with @@PRODUCT_STAGE@@ replaced, extract on the Dell, build ImageDump.exe (console, release) with the Dell toolchain, copy the corpus beside it
  decode   queue the `decode` Sandbox job (N fresh processes), fetch run-NN.zip into OUT/windows/run-NN/
The Sandbox worker is shared: this uses the existing FIFO queue (client.submit) and never starts, resets or restarts it, and never touches C:\\sbq\\state\\longrun-active.json."""
import argparse, json, subprocess, sys, time, zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO / "factory/tools/sandbox"))
import client  # noqa: E402

WIN = r"D:\Claude\swiftright\.factory-work\hosts\i1"
SSH = ["ssh", "-o", "BatchMode=yes", "win"]


def sh(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode and not kw.get("check") is False:
        sys.exit(f"FAILED {' '.join(map(str, cmd))[:160]}\n{(r.stdout + r.stderr)[-1500:]}")
    return r


def win(ps):
    return subprocess.run(SSH + [ps], capture_output=True, text=True)


def fwd(p): return p.replace("\\", "/")


def stage(ref=None):
    r = sh([sys.executable, str(REPO / "factory/tools/stage-product.py")] + (["--ref", ref] if ref else ["--working-tree"]))
    name = r.stdout.strip().splitlines()[-1]
    print("stage", name); return name


def build(stage_name):
    ts = time.strftime("%Y%m%d-%H%M%S")
    stage_dir = rf"D:\Claude\swiftright\.factory-work\product-stage\{stage_name}"
    zp = HERE / f".package-{ts}.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted((HERE / "dump-host").rglob("*")):
            if f.is_file() and ".build" not in f.parts and "scratch" not in f.parts:
                rel = f.relative_to(HERE / "dump-host").as_posix()
                z.writestr(rel, f.read_text().replace("@@PRODUCT_STAGE@@", fwd(stage_dir)) if f.name == "Package.swift" else f.read_bytes())
    win(f"New-Item -ItemType Directory -Force {WIN} | Out-Null")
    sh(["scp", "-q", str(zp), f"win:{fwd(WIN)}/package-{ts}.zip"])
    sh(["scp", "-q", str(HERE / "build-dump.ps1"), f"win:{fwd(WIN)}/build-dump.ps1"])
    zp.unlink()
    pkg = rf"{WIN}\package"
    r = win(f"if(Test-Path {pkg}){{Move-Item {pkg} D:\\Claude\\swiftright\\.work\\i1-package-{ts}}}; Expand-Archive {WIN}\\package-{ts}.zip {pkg}; if(Test-Path {WIN}\\corpus){{Move-Item {WIN}\\corpus D:\\Claude\\swiftright\\.work\\i1-corpus-{ts}}}; New-Item -ItemType Directory {WIN}\\corpus | Out-Null")
    sh(["scp", "-q", "-r", str(HERE / "corpus") + "/.", f"win:{fwd(WIN)}/corpus/"])
    t = time.time()
    r = win(f"powershell -NoProfile -ExecutionPolicy Bypass -File {WIN}\\build-dump.ps1 -Pkg {pkg}")
    sh(["scp", "-q", f"win:{fwd(pkg)}/build.log", str(HERE / "runs" / "windows-build.log")], check=False)
    print("build exit", r.returncode, f"{time.time() - t:.0f}s")
    if r.returncode:
        print((HERE / "runs" / "windows-build.log").read_text(errors="replace")[-3500:]); sys.exit(1)


def decode(runs, out, env=None):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    exe = rf"{WIN}\package\scratch\x86_64-unknown-windows-msvc\release\ImageDump.exe"
    jid, st, res = client.run_job("decode", dict(exe=exe, corpus=rf"{WIN}\corpus", runs=runs, old=(runs > 0), **({"env": env} if env else {})), out / "_job", 600 + runs * 40)
    print(jid, st.get("state"), "ok=", res.get("ok"), res.get("error", ""))
    zips = sorted((out / "_job" / "out").glob("run-*.zip"))
    for z in zips:
        d = out / "windows" / z.stem
        d.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(z) as zf: zf.extractall(d)
    (out / "result.json").write_text(json.dumps(res, indent=1))
    print(len(zips), "run dumps ->", out / "windows")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("cmd", choices=["stage", "build", "decode"]); ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--out", default=str(HERE / "runs" / time.strftime("%Y%m%d-%H%M%S"))); ap.add_argument("--stage", default=None); ap.add_argument("--ref", default=None, help="stage this git ref (git archive) instead of the working tree"); ap.add_argument("--env", action="append", default=[], help="NAME=VALUE for the decode job")
    a = ap.parse_args()
    (HERE / "runs").mkdir(exist_ok=True)
    if a.cmd == "stage": stage(a.ref)
    elif a.cmd == "build": build(a.stage or stage(a.ref))
    else: decode(a.runs, a.out, dict(e.split('=', 1) for e in a.env))
