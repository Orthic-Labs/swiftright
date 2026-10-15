#!/usr/bin/env python3
"""Run the three product unit suites on the Mac from a git archive (never the working tree), on the internal disk, and keep the logs.

  python3 factory/tools/mac-stage-test.py --ref HEAD --log-dir <dir>      (the Windows counterpart is factory/tools/pair/stage-test.ps1 on the staged tree)

Archive of PATHS at <ref> -> ~/Library/Caches/SwiftRightFactory/mac-test/<short sha>-<tree8>/ (same layout as the Windows stage, same tree hash),
then `swift test --jobs 1` per package with the default build system. One log per package in --log-dir, and a SUMMARY.json with the executed/skipped/failed
counts parsed from the logs. Exit 0 only when every package passes. The scratch tree is moved to ~/.Trash when --clean is given."""
import argparse, hashlib, io, json, re, subprocess, sys, tarfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PACKAGES = ["probes/sr0-s/fresh-runtime", "packages/SwiftRightHost", "packages/SwiftRightBridge"]
PATHS = ["packages/SwiftRightBridge", "packages/SwiftRightHost", "probes/sr0-s/fresh-runtime",
         "factory/pipeline/blocks-w0-i1/corpus", "factory/pipeline/blocks-w0-i1/expected"]   # the last two are test data of ImagePolicyTests (found from #filePath; absent = the tests skip)
EXCLUDE = ["probes/sr0-s/fresh-runtime/out", "probes/sr0-s/fresh-runtime/.build"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD"); ap.add_argument("--log-dir", required=True); ap.add_argument("--clean", action="store_true")
    a = ap.parse_args()
    commit = subprocess.run(["git", "-C", str(REPO), "rev-parse", a.ref], capture_output=True, text=True, check=True).stdout.strip()
    tar = subprocess.run(["git", "-C", str(REPO), "archive", "--format=tar", commit, "--", *PATHS], capture_output=True, check=True).stdout
    files = {}
    with tarfile.open(fileobj=io.BytesIO(tar)) as t:
        for m in t.getmembers():
            if m.isfile() and not any(m.name.startswith(e + "/") for e in EXCLUDE):
                files[m.name] = t.extractfile(m).read()
    h = hashlib.sha256()
    for n in sorted(files):
        h.update(n.encode() + b"\0" + hashlib.sha256(files[n]).digest())   # same tree hash as stage-product.py
    name = f"{commit[:9]}-{h.hexdigest()[:8]}"
    root = Path.home() / "Library/Caches/SwiftRightFactory/mac-test" / name
    if not root.exists():
        for n, data in files.items():
            p = root / n; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(data)
    logs = Path(a.log_dir); logs.mkdir(parents=True, exist_ok=True)
    summary = dict(stage=name, commit=commit, host="mac", packages={})
    ok = True
    for pkg in PACKAGES:
        log = logs / (pkg.replace("/", "_") + ".log")
        with log.open("w") as f:
            r = subprocess.run(["swift", "test", "--package-path", str(root / pkg), "--scratch-path", str(root / ".scratch" / pkg.replace("/", "_")), "--jobs", "1"],
                               stdout=f, stderr=subprocess.STDOUT)
        text = log.read_text(errors="replace")
        m = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures?", text) or re.findall(r"Executed (\d+) tests?, with (\d+) failures?", text)
        last = m[-1] if m else None
        summary["packages"][pkg] = dict(exit=r.returncode, executed=int(last[0]) if last else None, skipped=int(last[1]) if last and len(last) == 3 else 0, failures=int(last[-1]) if last else None, log=str(log))
        ok = ok and r.returncode == 0
        print(pkg, summary["packages"][pkg], flush=True)
    (logs / "SUMMARY.json").write_text(json.dumps(summary, indent=1))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
