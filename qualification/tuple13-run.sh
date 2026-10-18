#!/bin/sh
# Tuple13 qualification launcher. Validation is read-only; caller owns Dell lock.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TUPLE=${TUPLE:-$ROOT/qualification/tuple13-candidate.json}

python3 -I - "$TUPLE" <<'PY'
import json, re, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    d = json.load(f)
need = {"windows_renderer", "windows_fixture_exe", "windows_smoke_exe", "old_msix", "new_msix", "old_dmg", "new_dmg"}
if d.get("schema") != "sr0-a.tuple/v1" or d.get("name") != "tuple13-candidate":
    raise SystemExit("tuple13 candidate schema/name mismatch")
m = d.get("members", {})
if set(m) != need:
    raise SystemExit("tuple13 candidate members must equal qualification runner pins")
missing = sorted(k for k, v in m.items() if not isinstance(v, dict) or not re.fullmatch(r"[0-9a-f]{64}", str(v.get("sha256", ""))) or not v.get("source"))
if missing:
    raise SystemExit("tuple13 candidate still missing hash/source receipt: " + ",".join(missing))
print("TUPLE12_CANDIDATE_OK")
PY

confirm=0
dry=0
for arg in "$@"; do
    [ "$arg" = "--confirm-windows-gui" ] && confirm=1
    [ "$arg" = "--dry-run" ] && dry=1
done
if [ "$confirm" -ne 1 ] && [ "$dry" -ne 1 ]; then
    echo "refusing live tuple12 run without --confirm-windows-gui (use --dry-run for plan)" >&2
    exit 2
fi
exec python3 -I "$ROOT/qualification/run.py" run --tuple "$TUPLE" --runs 20 --win-runs 20 "$@"
