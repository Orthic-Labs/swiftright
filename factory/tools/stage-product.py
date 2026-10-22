#!/usr/bin/env python3
"""Stage ONE product tree (runtime + bridge + SwiftRightHost) on the Dell for every case package to build against.

  python3 factory/tools/stage-product.py [--ref HEAD] [--working-tree] [--print]

Default: `git archive <ref>` of the product paths (never working-tree bytes), copied to
D:\\Claude\\swiftright\\.factory-work\\product-stage\\<short sha>-<tree8>\\ with the repository layout preserved (the packages reference each other
by relative path), plus STAGE.json (commit, tree hash, paths, mode). An existing stage dir is reused untouched.
--working-tree stages the on-disk bytes instead (development only; STAGE.json says dirty=true and pair.py prints it).
Prints the stage name on the last line. pair.py --stage <name> builds the cases against it."""
import argparse, hashlib, io, json, subprocess, sys, tarfile, time, zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PATHS = ["packages/SwiftRightBridge", "packages/SwiftRightHost", "packages/SwiftRightCombine", "probes/sr0-s/fresh-runtime",
         "factory/pipeline/blocks-w0-i1/corpus", "factory/pipeline/blocks-w0-i1/expected"]   # the last two are test data of ImagePolicyTests (found from #filePath; absent = the tests skip)
EXCLUDE = ["probes/sr0-s/fresh-runtime/out", "probes/sr0-s/fresh-runtime/.build", "packages/SwiftRightCombine/Probe"]
WIN_STAGE = r"D:\Claude\swiftright\.factory-work\product-stage"
SSH = ["ssh", "-o", "BatchMode=yes", "win"]


def git(*a):
    return subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, check=True).stdout


def files_from_git(ref):
    tar = git("archive", "--format=tar", ref, "--", *PATHS)
    out = {}
    with tarfile.open(fileobj=io.BytesIO(tar)) as t:
        for m in t.getmembers():
            if m.isfile() and not any(m.name.startswith(e + "/") for e in EXCLUDE):
                out[m.name] = t.extractfile(m).read()
    return out


def files_from_tree():
    out = {}
    listed = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *PATHS).decode().split("\0")
    for name in listed:
        p = REPO / name
        if name and p.is_file() and not any(name.startswith(e + "/") for e in EXCLUDE):
            out[name] = p.read_bytes()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD"); ap.add_argument("--working-tree", action="store_true"); ap.add_argument("--print", action="store_true")
    a = ap.parse_args()
    commit = git("rev-parse", a.ref).decode().strip()
    files = files_from_tree() if a.working_tree else files_from_git(commit)
    h = hashlib.sha256()
    for n in sorted(files):
        h.update(n.encode() + b"\0" + hashlib.sha256(files[n]).digest())
    tree = h.hexdigest()
    name = f"{commit[:9]}-{tree[:8]}" + ("-dirty" if a.working_tree else "")
    meta = dict(name=name, commit=commit, ref=a.ref, mode="working-tree" if a.working_tree else "git-archive", dirty=a.working_tree,
                treeSha256="sha256:" + tree, files=len(files), paths=PATHS, stagedUtc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    if a.print:
        print(json.dumps(meta, indent=1)); return
    dest = rf"{WIN_STAGE}\{name}"
    probe = subprocess.run(SSH + [f'if (Test-Path {dest}\\STAGE.json) {{ "present" }} else {{ "absent" }}'], capture_output=True, text=True)
    if probe.stdout.strip().endswith("present"):
        print(f"stage {name} already staged: reused unchanged"); print(name); return
    zp = REPO / f".stage-{name}.zip"
    try:
        with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
            for n in sorted(files):
                z.writestr(n, files[n])
            z.writestr("STAGE.json", json.dumps(meta, indent=1))
        subprocess.run(SSH + [f'New-Item -ItemType Directory -Force {WIN_STAGE} | Out-Null'], check=True)
        subprocess.run(["scp", "-q", str(zp), f"win:{WIN_STAGE.replace(chr(92), '/')}/{name}.zip"], check=True)
        r = subprocess.run(SSH + [f'$ErrorActionPreference="Stop"; Expand-Archive {WIN_STAGE}\\{name}.zip {dest}; Move-Item {WIN_STAGE}\\{name}.zip D:\\Claude\\swiftright\\.work\\{name}-stage.zip -Force; "ok"'],
                           capture_output=True, text=True)
        if "ok" not in r.stdout:
            sys.exit(f"stage extract failed: {r.stdout}{r.stderr}")
    finally:
        zp.unlink(missing_ok=True)
    print(f"staged {name}: {len(files)} files, tree {tree[:16]}, {'WORKING TREE (dirty)' if a.working_tree else 'git archive ' + commit[:9]}")
    print(name)


if __name__ == "__main__":
    main()
