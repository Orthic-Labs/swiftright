#!/usr/bin/env python3
"""The ONE place the Mac tooling chooses where build output and launchable binaries live.

  python3 factory/tools/cache_paths.py status              sizes, free space, caps (read only)
  python3 factory/tools/cache_paths.py sweep [--report]    move stale/over-cap internal entries to /Volumes/D/scratch/swiftright/swiftright-cache-moved/<date>/ (--report: print the plan, move nothing)
  python3 factory/tools/cache_paths.py path build|run LANE print (and create) a lane path, for shell tools
  python3 factory/tools/cache_paths.py preflight LANE      free-space gate for a new Mac build (warn < 40 GB, refuse < 15 GB)
  python3 factory/tools/cache_paths.py finish LANE [--keep-build]

Two roots, because of two facts: running an executable from /Volumes/D raises a TCC removable-volume prompt on Adrian's screen, while compiling and linking
there does not (the compiler and linker are system binaries; verified, see docs/sr1-decisions.md), and the internal disk is small.
  BUILD root  /Volumes/D/scratch/swiftright/swiftright-cache/<lane>/                       SwiftPM --scratch-path, swiftc module caches, intermediates. Never executed from.
  RUN root    ~/Library/Caches/SwiftRightFactory/run/<lane>/            only the final executables / app bundles copied out to be launched. Capped at 2 GB (LRU eviction).
  MOVED       /Volumes/D/scratch/swiftright/swiftright-cache-moved/<YYYYMMDD>/             where the sweep moves things. Nothing here is ever deleted by this tool (workspace rule: move, never rm).
SWIFTRIGHT_CACHE_ROOT=<dir> (compatibility override) puts both roots under <dir> (<dir>/build/<lane>, <dir>/run/<lane>); the sweep, caps and gates still apply to it.
Existing lanes (old internal paths such as .../SwiftRightFactory/pair/<case>) are left alone by new code; the sweep moves them once they are 24 h old and not touched in the last 4 h."""
import os, shutil, subprocess, sys, time
from pathlib import Path

GB = 1 << 30
WARN_FREE_GB, REFUSE_FREE_GB = 40, 15       # internal free space: warn below 40, refuse a new Mac build below 15
RUN_CAP_BYTES = 2 * GB                      # run root total
LEGACY_CAP_BYTES = 6 * GB                   # old-style internal entries (pre-helper lanes) kept at most this much after the age rule
STALE_SECONDS = 24 * 3600                   # internal entries older than this are moved
ACTIVE_SECONDS = 4 * 3600                   # anything modified within this window is never moved (a lane may be in flight)
DONE = ".lane-done"                         # marker a finished build lane carries; the sweep may then move it from /Volumes/D too

HOME = Path.home()
INTERNAL = HOME / "Library/Caches/SwiftRightFactory"
MOVED = Path(os.environ.get("SWIFTRIGHT_CACHE_MOVED") or "/Volumes/D/scratch/swiftright/swiftright-cache-moved")   # CI runners set SWIFTRIGHT_CACHE_MOVED (no /Volumes/D there)
_override = os.environ.get("SWIFTRIGHT_CACHE_ROOT")
if _override:
    BUILD_ROOT, RUN_ROOT = Path(_override) / "build", Path(_override) / "run"
else:
    BUILD_ROOT, RUN_ROOT = Path("/Volumes/D/scratch/swiftright/swiftright-cache"), INTERNAL / "run"


def _lane(lane):
    lane = str(lane).strip().replace("/", "_")
    if not lane or lane in (".", ".."): raise ValueError(f"bad lane name {lane!r}")
    return lane


def build_root(lane):
    """Scratch for compilers and SwiftPM. On /Volumes/D: compile and link there, never launch from there."""
    p = BUILD_ROOT / _lane(lane); p.mkdir(parents=True, exist_ok=True)
    (p / DONE).unlink(missing_ok=True)      # a reused lane is live again
    return p


def run_root(lane):
    """Internal directory for the binaries to launch. Touches the lane (LRU) and enforces the 2 GB cap on the other lanes."""
    p = RUN_ROOT / _lane(lane); p.mkdir(parents=True, exist_ok=True)
    os.utime(p)
    _evict_run(keep=p)
    return p


def free_gb():
    return shutil.disk_usage(HOME).free / GB


def preflight(what="mac build", build=True):
    """Early warning on every driver run; refuse to start a new Mac build when the internal disk is nearly full."""
    f = free_gb()
    if f < WARN_FREE_GB:
        print(f"WARNING: internal disk has {f:.1f} GB free (< {WARN_FREE_GB} GB). Run: python3 factory/tools/cache_paths.py sweep", file=sys.stderr, flush=True)
    if build and f < REFUSE_FREE_GB:
        sys.exit(f"REFUSED: {what} not started, internal disk has {f:.1f} GB free (< {REFUSE_FREE_GB} GB). Run: python3 factory/tools/cache_paths.py sweep")
    return f


def finish_lane(lane, ok=True, keep_build=False):
    """Call when a lane or driver finishes. On success the run root is moved out (nothing is deleted) and the build root is marked for the sweep. On failure everything stays for diagnosis."""
    if not ok: return
    p = RUN_ROOT / _lane(lane)
    if p.exists(): _move(p, MOVED / time.strftime("%Y%m%d") / "run")
    b = BUILD_ROOT / _lane(lane)
    if b.exists() and not keep_build: (b / DONE).touch()


def _du(path):
    r = subprocess.run(["/usr/bin/du", "-sk", str(path)], capture_output=True, text=True)
    try: return int(r.stdout.split()[0]) * 1024
    except (IndexError, ValueError): return 0


def _newest(path, horizon):
    """Newest mtime under path, stopping early once something newer than horizon is seen (the entry is active)."""
    best = path.lstat().st_mtime
    if best >= horizon or not path.is_dir() or path.is_symlink(): return best
    stack = [path]
    while stack:
        try:
            with os.scandir(stack.pop()) as it:
                for e in it:
                    try: m = e.stat(follow_symlinks=False).st_mtime
                    except OSError: continue
                    best = max(best, m)
                    if best >= horizon: return best
                    if e.is_dir(follow_symlinks=False): stack.append(e.path)
        except OSError: continue
    return best


def _move(src, dest_dir):
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src.name
    if dest.exists(): dest = dest_dir / f"{src.name}.{int(time.time())}"
    r = subprocess.run(["/bin/mv", str(src), str(dest)], capture_output=True, text=True)   # move, never remove (workspace hook blocks permanent deletes)
    if r.returncode: print(f"  move failed {src}: {r.stderr.strip()}", file=sys.stderr)
    return dest


def _entries(root):
    """Sweepable units: lane dirs under run/ and the old containers (pair/, sr1/, mac-test/ ...), else top-level dirs."""
    out = []
    if not root.is_dir(): return out
    for top in sorted(root.iterdir()):
        if top.name == "run" or top.is_symlink() or not top.is_dir(): continue
        subs = [s for s in sorted(top.iterdir()) if s.is_dir() and not s.is_symlink()]
        out += subs if top.name in ("pair", "sr1", "mac-test") and subs else [top]
    return out


def _evict_run(keep=None):
    if not RUN_ROOT.is_dir(): return
    lanes = [(l.stat().st_mtime, l, _du(l)) for l in RUN_ROOT.iterdir() if l.is_dir()]
    total = sum(s for _, _, s in lanes)
    now = time.time()
    for m, l, s in sorted(lanes, key=lambda x: x[0]):
        if total <= RUN_CAP_BYTES: break
        if (keep is not None and l == keep) or now - _newest(l, now - ACTIVE_SECONDS) < ACTIVE_SECONDS: continue   # never evict the caller's lane or a lane active in the last 4 h
        _move(l, MOVED / time.strftime("%Y%m%d") / "run"); total -= s


def sweep(report=False, out=sys.stdout):
    now = time.time(); horizon = now - ACTIVE_SECONDS
    p = lambda *a: print(*a, file=out, flush=True)
    p(f"internal free {free_gb():.1f} GB; internal root {INTERNAL}; build root {BUILD_ROOT}; run root {RUN_ROOT} (cap {RUN_CAP_BYTES // GB} GB)")
    plan, kept, moved_bytes, total = [], [], 0, 0
    rows = []
    for e in _entries(INTERNAL) + [l for l in (RUN_ROOT.iterdir() if RUN_ROOT.is_dir() else []) if l.is_dir()]:
        newest = _newest(e, horizon); size = _du(e); total += size
        rows.append((e, size, newest, e.parent == RUN_ROOT))
    run_total = sum(s for e, s, n, r in rows if r)
    legacy = sorted([r for r in rows if not r[3]], key=lambda r: r[2])       # oldest first
    legacy_total = sum(r[1] for r in legacy)
    for e, size, newest, is_run in sorted(rows, key=lambda r: r[2]):
        age_h = (now - newest) / 3600
        if newest >= horizon: kept.append((e, size, age_h, "active (< 4 h)")); continue
        if is_run:
            if (now - newest) > STALE_SECONDS or run_total > RUN_CAP_BYTES: plan.append((e, size, age_h, "run root over cap / stale")); run_total -= size
            else: kept.append((e, size, age_h, "run lane"))
        elif (now - newest) > STALE_SECONDS: plan.append((e, size, age_h, "older than 24 h"))
        elif legacy_total - sum(x[1] for x in plan if not x[0].is_relative_to(RUN_ROOT)) > LEGACY_CAP_BYTES: plan.append((e, size, age_h, "legacy over cap"))
        else: kept.append((e, size, age_h, "recent"))
    for e, size, age_h, why in plan: p(f"  {'WOULD MOVE' if report else 'MOVE':10} {size / GB:6.2f} GB  {age_h:6.1f} h  {e}  ({why})")
    for e, size, age_h, why in kept: p(f"  keep       {size / GB:6.2f} GB  {age_h:6.1f} h  {e}  ({why})")
    dest = MOVED / time.strftime("%Y%m%d")
    if not report:
        for e, size, _, _ in plan:
            _move(e, dest / e.relative_to(INTERNAL).parent if e.is_relative_to(INTERNAL) else dest / "other"); moved_bytes += size
    # finished build lanes on /Volumes/D
    done = [b for b in (BUILD_ROOT.iterdir() if BUILD_ROOT.is_dir() else []) if (b / DONE).exists() and now - (b / DONE).stat().st_mtime > STALE_SECONDS]
    for b in done:
        p(f"  {'WOULD MOVE' if report else 'MOVE':10} (D) {b}  (finished build lane)")
        if not report: _move(b, MOVED / time.strftime("%Y%m%d") / "build")
    p(f"internal entries total {total / GB:.2f} GB; " + (f"plan moves {sum(x[1] for x in plan) / GB:.2f} GB to {dest}" if report else f"moved {moved_bytes / GB:.2f} GB to {dest}") + f"; internal free now {free_gb():.1f} GB")
    return plan


def status():
    sweep(report=True)


def main(argv):
    if len(argv) < 2: print(__doc__); return 2
    c = argv[1]
    if c in ("status",): status()
    elif c == "sweep": sweep(report="--report" in argv or "--dry-run" in argv)
    elif c == "path" and len(argv) == 4 and argv[2] in ("build", "run"): print((build_root if argv[2] == "build" else run_root)(argv[3]))
    elif c == "preflight" and len(argv) >= 3: preflight(argv[2])
    elif c == "finish" and len(argv) >= 3: finish_lane(argv[2], keep_build="--keep-build" in argv)
    else: print(__doc__); return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
