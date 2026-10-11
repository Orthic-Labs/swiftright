#!/bin/sh
# Root-run source packet for existing trusted signed F1 recorder, exactly 20 runs.
# It writes metadata before native work, keeps outputs fresh, & never deletes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
: "${REC:?set REC to internal-disk existing signed F1MacRecord executable}"
: "${FA:?set FA to internal-disk FixtureApp executable}"
: "${ASM:?set ASM to internal-disk F1Assemble executable}"
OUT=${1:?usage: tuple12-mac-f1-run.sh FRESH_OUT_DIR}
case "$OUT" in "$HOME"/*) ;; *) echo "output must be under HOME on internal disk: $OUT" >&2; exit 2;; esac
[ ! -e "$OUT" ] || { echo "output exists; choose fresh namespace: $OUT" >&2; exit 2; }
mkdir "$OUT"

python3 - "$ROOT" "$OUT" "$REC" "$FA" "$ASM" <<'PY'
import hashlib, json, os, pathlib, sys
root, out, rec, fa, asm = map(pathlib.Path, sys.argv[1:])
packet = root / "qualification/tuple12-mac-f1-packet.json"
def item(label, path):
    path = path.expanduser()
    if not path.is_absolute() or path.is_symlink() or not path.is_file(): raise SystemExit(f"bad native input: {path}")
    real = pathlib.Path(os.path.realpath(path))
    if str(real).startswith("/Volumes/"): raise SystemExit(f"external native input: {real}")
    data = path.read_bytes()
    return {"label": label, "path": str(path), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
if not packet.is_file() or packet.is_symlink(): raise SystemExit("source packet missing or unsafe")
data = {"kind": "sr0-tuple12-mac-f1-capture-start-v1", "sourceCommit": "0e201571e4320a3b6ccce14313fd2ad67e523904", "candidateSourceCommit": "4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2", "packetSha256": hashlib.sha256(packet.read_bytes()).hexdigest(), "nativeInputs": [item("F1MacRecord", rec), item("FixtureApp", fa), item("F1Assemble", asm)], "config": "F1", "runs": 20}
(out / "capture-start.json").open("x", encoding="utf-8").write(json.dumps(data, indent=2) + "\n")
PY

RUNS=${RUNS:-20}
[ "$RUNS" = 20 ] || { echo "RUNS must equal exactly 20" >&2; exit 2; }
"$ROOT/qualification/tuple12-mac20.sh" "$OUT/runs" F1
