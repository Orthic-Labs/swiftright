#!/usr/bin/env python3
"""Mac-side client of the long-lived Windows Sandbox worker on the Dell (see start-worker.ps1).

  client.py sync                      copy the Dell-side + guest scripts to D:\\Claude\\swiftright\\.sandbox (does not touch the running Sandbox)
  client.py start                     run start-worker.ps1 on the Dell (no-op when a worker heartbeat is fresh; at most once per day)
  client.py status                    heartbeat age, Sandbox processes, window state (IsIconic / foreground), recent jobs
  client.py capture EXE [--runs N]    run FactoryProbe capture jobs in the Sandbox; PNGs and done.json to --out
  client.py w08 METHOD [--delays 240] run one W08 method (tier2-repair | tier2-feed-down | tier2-uninstall) in the Sandbox
  client.py w08-reset                 clean + verify the W08 package state only
  client.py command 'powershell text' run a command in the Sandbox desktop
  client.py window min|offscreen|bottom  set the Sandbox client window state (min = minimised; offscreen = not minimised, never visible)

Jobs are JSON files in the Dell queue; results come back from results\\<id>\\ (scp). Build stays on the Dell host over SSH (swift build opens no windows)."""
import argparse, json, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SSH = ["ssh", "-o", "BatchMode=yes", "win"]
ROOT = r"D:\Claude\swiftright\.sandbox"


def fwd(p):
    return p.replace("\\", "/")


def run(cmd, check=True, timeout=None):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode:
        sys.exit(f"FAILED ({r.returncode}): {' '.join(map(str, cmd))[:200]}\n{(r.stdout + r.stderr)[-1500:]}")
    return r


def ps(text, **kw):
    return run(SSH + [text], **kw)


def scp_to(files, dest_dir):
    run(["scp", "-q", *map(str, files), f"win:{fwd(dest_dir)}/"])


def sync():
    ps(f'New-Item -ItemType Directory -Force {ROOT}\\guest, {ROOT}\\guest\\w08, {ROOT}\\queue, {ROOT}\\results, {ROOT}\\state | Out-Null')
    scp_to(sorted(HERE.glob("*.ps1")), ROOT)
    scp_to(sorted((HERE / "guest").glob("*.ps1")) + [HERE / "guest/logon.cmd", REPO / "factory/tools/pair/capture.ps1"], ROOT + r"\guest")
    scp_to([REPO / "qualification/clean-machine/windows/guest/w08-recovery-guest.ps1", REPO / "examples/SliceApp/scripts/serve-local-feed.ps1"], ROOT + r"\guest\w08")


def sync_capture_tool(tools_dir):
    """refresh only the capture script the guest runs (pair.py --sandbox calls this so the guest always uses the checkout's capture.ps1)"""
    scp_to([Path(tools_dir) / "capture.ps1"], ROOT + r"\guest")


def status():
    r = ps(f'powershell -NoProfile -ExecutionPolicy Bypass -File {ROOT}\\start-worker.ps1 -Status', check=False, timeout=120)
    return r.stdout + r.stderr


def window(mode):
    """min | offscreen | bottom: set the Sandbox client window state in the interactive session (foreground is handed back if the Sandbox ever takes it)"""
    r = ps(f'. {ROOT}\\lib-interactive.ps1; Invoke-Interactive -File {ROOT}\\window-set.ps1 -FileArgs "-Mode {mode} -Seconds 3 -Out {ROOT}\\state\\window-set.txt" -WorkDir {ROOT}\\state\\task -TimeoutSec 60 | Out-Null; Get-Content {ROOT}\\state\\window-set.txt', check=False, timeout=120)
    return r.stdout.strip()


def worker_up():
    r = ps(f'try {{ [math]::Round(((Get-Date).ToUniversalTime() - (Get-Item {ROOT}\\state\\hb.json).LastWriteTimeUtc).TotalSeconds,1) }} catch {{ 99999 }}', check=False)
    try:
        return float(r.stdout.strip().splitlines()[-1]) < 15
    except Exception:
        return False


def submit(kind, args, timeout_sec=600, jid=None):
    jid = jid or f"{time.strftime('%Y%m%d-%H%M%S')}-{kind}-{int(time.time() * 1000) % 100000}"
    tmp = HERE / f".{jid}.json.tmp"
    tmp.write_text(json.dumps(dict(id=jid, kind=kind, timeoutSec=timeout_sec, args=args)))
    try:
        run(["scp", "-q", str(tmp), f"win:{fwd(ROOT)}/queue/{jid}.part"])
    finally:
        tmp.unlink(missing_ok=True)
    ps(f'Move-Item {ROOT}\\queue\\{jid}.part {ROOT}\\queue\\{jid}.json')
    return jid


def wait(jid, timeout_sec):
    """one SSH call that polls on the Dell; returns the status.json dict (state=timeout-client when the DONE marker never appeared)"""
    d = f"{ROOT}\\results\\{jid}"
    r = ps(f'$e=(Get-Date).AddSeconds({int(timeout_sec)}); while(-not (Test-Path {d}\\DONE) -and (Get-Date) -lt $e){{Start-Sleep -Milliseconds 500}}; if(Test-Path {d}\\DONE){{Get-Content {d}\\status.json -Raw}}else{{\'{{"state":"timeout-client"}}\'}}',
           check=False, timeout=timeout_sec + 60)
    try:
        return json.loads(r.stdout)
    except Exception:
        return dict(state="unreadable", raw=r.stdout[-500:] + r.stderr[-500:])


def fetch(jid, dest, sub="*"):
    dest = Path(dest); dest.mkdir(parents=True, exist_ok=True)
    run(["scp", "-q", "-r", f"win:{fwd(ROOT)}/results/{jid}/{sub}", str(dest)], check=False)


def result(jid, dest):
    fetch(jid, dest, "result.json")
    p = Path(dest) / "result.json"
    return json.loads(p.read_text(encoding="utf-8-sig")) if p.is_file() else {}


def run_job(kind, args, dest, timeout_sec=600):
    if not worker_up():
        sys.exit("sandbox worker is not running (heartbeat stale): start it with `client.py start` (once per day; never per run)")
    jid = submit(kind, args, timeout_sec)
    st = wait(jid, timeout_sec + 30)
    fetch(jid, dest)
    return jid, st, result(jid, dest)


def capture(exe, runs, out, timeout_sec=None):
    """Sandbox replacement of session.ps1 + capture.ps1 for pair.py: PNGs (native-NN.png), done.json, host-NN logs land in `out`."""
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    jid, st, res = run_job("capture", dict(exe=exe, runs=runs), out / "_job", timeout_sec or runs * 90 + 300)
    jd = out / "_job"
    if (jd / "out").is_dir():
        for f in (jd / "out").iterdir():
            f.replace(out / f.name)
    return jid, st, res


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("sync"); sp.add_parser("start"); sp.add_parser("status"); wr = sp.add_parser("w08-reset"); wr.add_argument("--out", default=None)
    c = sp.add_parser("capture"); c.add_argument("exe"); c.add_argument("--runs", type=int, default=1); c.add_argument("--out", default="sandbox-capture")
    w = sp.add_parser("w08"); w.add_argument("method"); w.add_argument("--delays", default="240,360"); w.add_argument("--run-id", default=None); w.add_argument("--out", default=None); w.add_argument("--timeout", type=int, default=1500); w.add_argument("--max-attempts", type=int, default=8, help="induction attempts the harness may use (about 70 s each); bounds the job")
    wn = sp.add_parser("window"); wn.add_argument("mode", choices=["min", "offscreen", "bottom"])
    k = sp.add_parser("command"); k.add_argument("script"); k.add_argument("--out", default=None)
    a = ap.parse_args()
    if a.cmd == "sync":
        sync(); print("synced")
    elif a.cmd == "start":
        sync()
        r = ps(f'powershell -NoProfile -ExecutionPolicy Bypass -File {ROOT}\\start-worker.ps1', check=False, timeout=900)
        print(r.stdout + r.stderr); sys.exit(r.returncode)
    elif a.cmd == "window":
        print(window(a.mode))
    elif a.cmd == "status":
        print(status())
    elif a.cmd == "capture":
        jid, st, res = capture(a.exe, a.runs, a.out); print(jid, st.get("state"), json.dumps(res, indent=1))
    elif a.cmd in ("w08", "w08-reset"):
        method = getattr(a, "method", "")
        out = Path(getattr(a, "out", None) or f"sandbox-w08-{time.strftime('%Y%m%d-%H%M%S')}")
        args = dict(action="reset") if a.cmd == "w08-reset" else dict(action="run", method=method, delays=a.delays, runId=a.run_id or out.name, maxAttempts=a.max_attempts)
        jid, st, res = run_job("w08", args, out, getattr(a, "timeout", 600))
        print(jid, st.get("state"), "ok=%s pass=%s needs_fresh_sandbox=%s" % (res.get("ok"), res.get("pass"), res.get("needs_fresh_sandbox")), "->", out)
    elif a.cmd == "command":
        out = Path(a.out or f"sandbox-cmd-{time.strftime('%Y%m%d-%H%M%S')}")
        jid, st, res = run_job("command", dict(script=a.script), out, 300)
        print(st.get("state"), res); print((out / "out.txt").read_text(errors="replace") if (out / "out.txt").is_file() else "")


if __name__ == "__main__":
    main()
