#!/usr/bin/env python3
"""GitHub-runner side of factory pair sweeps (factory-pairs.yml). No Dell, no Sandbox, no /Volumes/D paths.

  python3 factory/tools/ci_pair.py plan       CASES=<text> CASES_FILE=<path> RUNS=N  -> matrix JSON (stdout) + GITHUB_OUTPUT
  python3 factory/tools/ci_pair.py stage      --work DIR                              git archive product paths -> DIR/product-stage/<name>; prints name
  python3 factory/tools/ci_pair.py renderer   --label L --dest DIR                    fetch the pinned render-windows artifact, verify sha256; prints DLL path
  python3 factory/tools/ci_pair.py mac        --case C --runs N --ts TS --root DIR    Mac side (pair.mac: pinned scale 2.5, scale guard)
  python3 factory/tools/ci_pair.py windows    --case C --runs N --ts TS --root DIR --work DIR --stage-dir S --renderer DLL --renderer-label L
  python3 factory/tools/ci_pair.py compare    --case C --runs N --ts TS --root DIR --results FILE   gates on merged captures, appends one results record

Layout under --root mirrors the repository: <root>/<case>/runs/<ts>/{mac,windows}/*.png, build.json (mac + scale guard), build-windows.json (stage, renderer).
Records use the local consolidation/results.jsonl shape (run_round6.py) plus runner fields.
Gates are pair.py's own (compare, recorded scale guard, semantic gate); nothing is tuned here."""
import argparse, contextlib, hashlib, importlib.util, io, json, os, re, shutil, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
import pair  # noqa: E402  (pair imports cache_paths; nothing is created at import)

REPO_SLUG = os.environ.get("GITHUB_REPOSITORY", "Orthic-Labs/swiftright")
GUEST = HERE / "sandbox" / "guest"
RENDERERS_DIR = REPO / "factory" / "renderers"   # committed pinned DLLs: <label>/swiftright_render.dll + SHA256
GUEST_SCRIPT = {"capture": "job-capture.ps1", "clock": "job-clock.ps1", "interact": "job-interact.ps1"}
# The capture script the clock and capture jobs run per launch: the same file client.py deploys to C:\sbq\guest on the Dell.
# The job passes it as args.captureScript; the guest scripts default to the sandbox path only when no path is passed.
CAPTURE_SCRIPT = HERE / "pair" / "capture.ps1"
NESTED_SCRIPT = {"capture": CAPTURE_SCRIPT, "clock": CAPTURE_SCRIPT}


def job_kind(clock, steps):
    return "clock" if clock is not None else "interact" if steps is not None else "capture"


def guest_scripts(kind):
    """Every script a job of this kind runs on the runner, so a missing file fails before a build or a job starts."""
    return [GUEST / GUEST_SCRIPT[kind]] + ([NESTED_SCRIPT[kind]] if kind in NESTED_SCRIPT else [])


def job_args(kind, exe, runs, renderer, clock=None, steps=None, flicker=False):
    args = dict(exe=str(exe), runs=runs, renderer=str(Path(renderer)))
    if kind == "clock":
        args["clock"] = list(clock)
    if kind == "interact":
        args.update(steps=steps, settleMs=500)
    if kind in NESTED_SCRIPT:
        args["captureScript"] = str(NESTED_SCRIPT[kind])
    if flicker:
        args["flickerProbe"] = True
    return args
# The pinned renderers. Each DLL is committed under factory/renderers/<label>/ (checked first); the CI artifact below is the fallback.
# Labels are the names the factory uses.
RENDERERS = {
    "renderer-0.9-925df9f3": dict(runId=38742361678, artifact="swiftright-render-925df9f3ae5edfd91c52a467e498502927b0ab56",
                                  sha256="6b6fc10c81741d27d74075c5fe9ed63a4259e1472ef092764081d2b55924e422"),
    # ABI 0.10 (decision H17): the explicit render scale. render-windows CI run 38841885720 on d449e4deed698f4ae46435cb756a4ce1791c6a0b.
    "renderer-0.10-d449e4de": dict(runId=38841885720, artifact="swiftright-render-d449e4deed698f4ae46435cb756a4ce1791c6a0b",
                                   sha256="b8f046977986e8a6d642ceac12f09182cc404bb9871304b6e5ab8fa39330da09"),
    # The same plus the settled-size log line at ready (the early-sample line removed). render-windows CI run 38842731404 on a15ebc5d14bef5128c0b8e531f66ffb15ebe9758.
    "renderer-0.10-a15ebc5d": dict(runId=38842731404, artifact="swiftright-render-a15ebc5d14bef5128c0b8e531f66ffb15ebe9758",
                                   sha256="c533438a0900bc5aeaee10661a70c9c3ee0e1d87e774a5ac4aea81589f25f996"),
    # Same ABI 0.10 plus the Mac multi-line pitch (decision G75(b): block height rounded once from the scale-1 pitch, fractional line advance). render-windows CI run 38991236961 on a79258d63703da15e1ea4ede1ee745388d136156 (68 Rust tests pass).
    "renderer-0.10-a79258d6": dict(runId=38991236961, artifact="swiftright-render-a79258d63703da15e1ea4ede1ee745388d136156",
                                   sha256="1a256d4594618a3a931b791b3c2d3f9996520301ba0928acde9e863f1c49bd11"),
}
BLOCK_LABELS = {"swiftui.slider": "37 slider", "swiftui.on-hover": "38 on-hover", "swiftui.uia-walk": "39 uia-walk",
                "swiftui.compat": "41 compat", "swiftui.ime-traps": "40 ime-traps"}
DEP = ("/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' "
       "processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'")   # same linker flags as factory/tools/pair/build.ps1


def sha256_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def slug(case_rel):
    return re.sub(r"[^A-Za-z0-9]+", "-", case_rel).strip("-")[-120:]


def case_path(case_rel):
    c = (REPO / case_rel).resolve()
    if not (c / "mac-source").is_dir() or not (c / "package").is_dir():
        sys.exit(f"not a pair case (needs mac-source/ and package/): {case_rel}")
    return c


def set_globals(case):
    """pair.py sets these in main(); compare() reads them."""
    pj = json.loads((case / "pair.json").read_text()) if (case / "pair.json").is_file() else {}
    pair.HAZE = int(pj.get("hazeTolerance", 0))
    pair.EDGE_AA = int(pj["edgeAATolerance"]["levels"]) if "edgeAATolerance" in pj else 32


def run_dir(root, case_rel, ts):
    d = Path(root) / case_rel / "runs" / ts
    d.mkdir(parents=True, exist_ok=True)
    return d


# ---------------------------------------------------------------- plan
def cmd_plan(a):
    text = os.environ.get("CASES", "") or ""
    cf = os.environ.get("CASES_FILE", "") or ""
    if cf:
        for line in (REPO / cf).read_text().splitlines():
            text += "\n" + line.split("#", 1)[0]
    cases = []
    for tok in re.split(r"[\s,]+", text):
        tok = tok.strip().strip("/")
        if tok and tok not in cases:
            cases.append(tok)
    if not cases:
        sys.exit("no cases: set the cases input or cases_file")
    for c in cases:
        case_path(c)
    runs = int(os.environ.get("RUNS", "3"))
    if not 1 <= runs <= 60:
        sys.exit("runs must be 1..60")
    matrix = {"include": [{"idx": i, "case": c, "slug": slug(c)} for i, c in enumerate(cases)]}
    print(json.dumps(matrix))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"matrix={json.dumps(matrix)}\n")
            f.write(f"count={len(cases)}\n")
            f.write(f"ts={time.strftime('%Y%m%d-%H%M%S', time.gmtime())}\n")


# ---------------------------------------------------------------- stage
def cmd_stage(a):
    spec = importlib.util.spec_from_file_location("stage_product", HERE / "stage-product.py")
    sp = importlib.util.module_from_spec(spec); spec.loader.exec_module(sp)
    commit = sp.git("rev-parse", a.ref).decode().strip()
    files = sp.files_from_git(commit)
    h = hashlib.sha256()
    for n in sorted(files):
        h.update(n.encode() + b"\0" + hashlib.sha256(files[n]).digest())
    tree = h.hexdigest()
    name = f"{commit[:9]}-{tree[:8]}"
    dest = Path(a.work) / "product-stage" / name
    if not (dest / "STAGE.json").is_file():
        for n, data in files.items():
            p = dest / n; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(data)
        meta = dict(name=name, commit=commit, ref=a.ref, mode="git-archive", dirty=False, treeSha256="sha256:" + tree,
                    files=len(files), paths=sp.PATHS, stagedUtc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        (dest / "STAGE.json").write_text(json.dumps(meta, indent=1))
    print(name)
    print(dest)


# ---------------------------------------------------------------- renderer
def cmd_renderer(a):
    spec = RENDERERS[a.label]
    # The committed copy comes first: CI artifacts expire (14 days), so the pin must not depend on them.
    local = RENDERERS_DIR / a.label / "swiftright_render.dll"
    if local.is_file():
        got = sha256_file(local)
        if got != spec["sha256"]:
            sys.exit(f"committed renderer sha256 mismatch: {local}: {got} != {spec['sha256']}")
        side = local.with_name("SHA256")
        if side.is_file() and side.read_text().split()[:1] != [spec["sha256"]]:
            sys.exit(f"committed SHA256 sidecar does not match the pin: {side}")
        print(local)
        return
    dest = Path(a.dest); dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(["gh", "run", "download", str(spec["runId"]), "--repo", REPO_SLUG, "--name", spec["artifact"], "--dir", str(dest)], check=True)
    dlls = [p for p in dest.rglob("swiftright_render.dll")]
    if len(dlls) != 1:
        sys.exit(f"expected one swiftright_render.dll in the artifact, found {len(dlls)}")
    got = sha256_file(dlls[0])
    if got != spec["sha256"]:
        sys.exit(f"renderer sha256 mismatch: {got} != {spec['sha256']}")
    print(dlls[0])


# ---------------------------------------------------------------- mac
def cmd_mac(a):
    case = case_path(a.case)
    out = run_dir(a.root, a.case, a.ts)
    set_globals(case)
    clock = pair.load_clock(case, None)
    ok = pair.mac(case, case.name, a.runs, out, clock, False)
    print(f"mac side {a.case}: scale guard {'pass' if ok else 'FAIL'}")
    if not ok:
        sys.exit(1)


# ---------------------------------------------------------------- windows
def copy_package(case, pkg, stage_dir):
    if pkg.exists():
        shutil.rmtree(pkg)
    for f in sorted((case / "package").rglob("*")):
        rel = f.relative_to(case / "package")
        if not f.is_file() or "scratch" in rel.parts:
            continue
        dst = pkg / rel; dst.parent.mkdir(parents=True, exist_ok=True)
        if f.name == "Package.swift":
            dst.write_text(f.read_text().replace("@@PRODUCT_STAGE@@", str(stage_dir).replace("\\", "\\\\")))
        else:
            shutil.copyfile(f, dst)


def cmd_windows(a):
    case = case_path(a.case)
    out = run_dir(a.root, a.case, a.ts)
    wdir = out / "windows"; wdir.mkdir(parents=True, exist_ok=True)
    sha = sha256_file(a.renderer)
    want = RENDERERS.get(a.renderer_label, {}).get("sha256")
    if want and sha != want:
        sys.exit(f"renderer sha256 {sha} != {want} ({a.renderer_label})")
    host = Path(a.work) / "hosts" / slug(a.case)
    host.mkdir(parents=True, exist_ok=True)
    pkg = host / "package"
    copy_package(case, pkg, Path(a.stage_dir))
    build_log = out / "windows-swift-build.log"
    t = time.time()
    with build_log.open("w") as log:
        r = subprocess.run(["swift", "build", "--build-system", "native", "--package-path", str(pkg), "--scratch-path", str(pkg / "scratch"),
                            "--jobs", "1", "-Xswiftc", "-j1", "-Xswiftc", "-num-threads", "-Xswiftc", "1", "-c", "release",
                            "-Xlinker", "/MANIFEST:EMBED", "-Xlinker", DEP, "-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"],
                           stdout=log, stderr=subprocess.STDOUT)
    exe = pkg / "scratch" / "x86_64-unknown-windows-msvc" / "release" / "FactoryProbe.exe"
    if r.returncode or not exe.is_file():
        sys.exit(f"windows build failed ({r.returncode}); see {build_log}")
    print(f"windows build ok {time.time() - t:.0f}s", flush=True)
    steps = pair.load_steps(case, None)
    clock = pair.load_clock(case, None)
    kind = job_kind(clock, steps)
    missing = [str(f) for f in guest_scripts(kind) if not f.is_file()]
    if missing:
        sys.exit(f"guest scripts for a {kind} job do not exist in the checkout: {missing}")
    if a.flicker_probe and kind == "clock":
        sys.exit("--flicker-probe is not implemented for a clock job")
    args = job_args(kind, exe, a.runs, a.renderer, clock=clock, steps=steps, flicker=a.flicker_probe)
    jobdir = Path(a.work) / "jobs" / slug(a.case)
    if jobdir.exists():
        shutil.rmtree(jobdir)
    jobdir.mkdir(parents=True)
    (jobdir / "job.json").write_text(json.dumps(dict(id=jobdir.name, kind=kind, timeoutSec=a.runs * 120 + 300, args=args)))
    timeout = a.runs * 120 + 300
    r = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                        str(GUEST / GUEST_SCRIPT[kind]), "-JobDir", str(jobdir)], timeout=timeout, check=False)
    jout = jobdir / "out"
    if jout.is_dir():
        for f in jout.iterdir():
            shutil.move(str(f), str(wdir / f.name))
    if (jobdir / "result.json").is_file():
        shutil.copy(jobdir / "result.json", out / "windows-job.json")
    done_p = wdir / "done.json"
    done = json.loads(done_p.read_text(encoding="utf-8-sig")) if done_p.is_file() else []
    bad = [d for d in done if d.get("status") != "ok"]
    ok = r.returncode == 0 and len(done) == a.runs and not bad
    stage = json.loads((Path(a.stage_dir) / "STAGE.json").read_text())
    guest = json.loads((jobdir / "result.json").read_text(encoding="utf-8-sig")) if (jobdir / "result.json").is_file() else {}
    info = dict(stage=stage, renderer=dict(path=str(a.renderer), label=a.renderer_label, sha256=sha), case=a.case, captureKind=kind, flickerProbe=a.flicker_probe,
                runner=dict(os=os.environ.get("RUNNER_OS", ""), image=os.environ.get("ImageOS", ""), video=guest.get("video"),
                            exeSha256=guest.get("exe_sha256"), rendererSha256=guest.get("renderer_sha256")),
                capture=dict(ok=ok, runs=a.runs, done=len(done), bad=bad[:5], guestOk=guest.get("ok"), guestError=guest.get("error")))
    (out / "build-windows.json").write_text(json.dumps(info, indent=1))
    print(f"windows capture {kind} {len(done) - len(bad)}/{a.runs} ok" + (f" first error: {bad[0]}" if bad else ""), flush=True)
    if not ok:
        sys.exit(f"windows capture failed (guest exit {r.returncode}); see {out}/build-windows.json")


# ---------------------------------------------------------------- compare
def merge_build(out):
    mac_p, win_p = out / "build.json", out / "build-windows.json"
    d = json.loads(mac_p.read_text()) if mac_p.is_file() else {}
    if win_p.is_file():
        w = json.loads(win_p.read_text())
        d["stage"], d["renderer"] = w["stage"], w["renderer"]
        d["windows"] = dict(runner=w["runner"], capture=w["capture"], captureKind=w["captureKind"])
    mac_p.write_text(json.dumps(d, indent=1))
    return d


def cmd_compare(a):
    case = case_path(a.case)
    out = run_dir(a.root, a.case, a.ts)
    t = time.time()
    rec = dict(stage=None, block=BLOCK_LABELS.get(case.parent.name, case.parent.name), case=a.case, n=a.runs, exit=1, out=str(out),
               secs=0, macRerun=False, recompared=False, tail=[], done=True, ts=a.ts, runnerRunId=os.environ.get("GITHUB_RUN_ID"))
    if not (out / "mac").is_dir() or not (out / "windows").is_dir():
        rec["tail"] = [f"missing side: mac={ (out / 'mac').is_dir() } windows={ (out / 'windows').is_dir() }"]
    else:
        set_globals(case)
        clock = pair.load_clock(case, None)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            d = merge_build(out)
            rec["stage"] = (d.get("stage") or {}).get("name")
            ok = pair.compare(out, a.runs, pair.load_exclusions(case, None), len(clock or []), pair.load_phases(case))
            guard = pair.recorded_scale_guard(out, False)
            ok = ok and guard
            sem = pair.semantic_gate(case, out)
            passed = ok if sem is None else (guard and sem and (ok or pair.semantic_decides(case)))
        text = buf.getvalue()
        print(text, end="")
        rec["exit"] = 0 if passed else 1
        rec["tail"] = [l for l in text.splitlines() if "Deprecat" not in l][-6:]
        rec["scaleGuard"] = ((d.get("mac") or {}).get("scaleGuard") or {}).get("status")
    rec["secs"] = round(time.time() - t)
    with open(a.results, "a") as f:
        f.write(json.dumps(rec) + "\n")
    print(f"{a.case}: {'PASS' if rec['exit'] == 0 else 'FAIL'} (stage {rec['stage']}, n={a.runs})", flush=True)
    sys.exit(rec["exit"])


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan")
    s = sub.add_parser("stage"); s.add_argument("--ref", default="HEAD"); s.add_argument("--work", required=True)
    r = sub.add_parser("renderer"); r.add_argument("--label", required=True); r.add_argument("--dest", required=True)
    for name in ("mac", "windows", "compare"):
        p = sub.add_parser(name)
        p.add_argument("--case", required=True); p.add_argument("--runs", type=int, required=True)
        p.add_argument("--ts", required=True); p.add_argument("--root", required=True)
        if name == "windows":
            p.add_argument("--work", required=True); p.add_argument("--stage-dir", required=True)
            p.add_argument("--renderer", required=True); p.add_argument("--renderer-label", required=True)
            p.add_argument("--flicker-probe", action="store_true")
        if name == "compare":
            p.add_argument("--results", required=True)
    a = ap.parse_args()
    {"plan": cmd_plan, "stage": cmd_stage, "renderer": cmd_renderer, "mac": cmd_mac, "windows": cmd_windows, "compare": cmd_compare}[a.cmd](a)


if __name__ == "__main__":
    main()
