# Root-only source-bound r11 sequence

Run from Mac internal disk for every compiler/native operation. `REPO` stays source/evidence checkout; `MAC_ROOT` is fresh internal scratch. Do not reuse prior capture IDs or output directories.

Use repository `factory/.venv/bin/python` for every packet script; its JSON Schema/RFC3339 checker matches factory validation. `/usr/bin/python3` is not admitted for materialization.

```sh
REPO=/Volumes/D/claude/swiftright
MAC_ROOT=/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/mac-padding-r11-count20-<fresh>
BASE=$REPO/factory/oracle/mac/padding-origin-r11-source-v1
PYTHON=$REPO/factory/.venv/bin/python
BASE_CASE=$BASE/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.json
BASE_MANIFEST=$BASE/manifests/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.manifest.json
mkdir -p "$MAC_ROOT"
cd "$REPO"
PYTHONPATH="$REPO" SWIFTRIGHT_REPO_ROOT="$REPO" "$PYTHON" "$BASE/prepare-r11-host.py" \
  --manifest "$BASE_MANIFEST" --case "$BASE_CASE" --output "$MAC_ROOT/host"
HOST_JSON=$MAC_ROOT/host/host-build-r1.json
HOST_HASH=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary"]["sha256"])' "$HOST_JSON")
HOST_SHORT=${HOST_HASH#sha256:}; HOST_SHORT=${HOST_SHORT:0:12}
GEN=$BASE/generated/$HOST_SHORT
PYTHONPATH="$REPO" SWIFTRIGHT_REPO_ROOT="$REPO" "$PYTHON" "$BASE/materialize-r11-case.py" \
  --base-case "$BASE_CASE" --base-manifest "$BASE_MANIFEST" --host-receipt "$HOST_JSON" \
  --output-case "$GEN/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h$HOST_SHORT.json" \
  --output-manifest "$GEN/manifests/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h$HOST_SHORT.manifest.json" \
  --output-tuple "$GEN/candidate-tuple.json"
FRESH_CASE=$(find "$GEN/cases" -type f -name '*.json' -print -quit)
FRESH_MANIFEST=$(find "$GEN/manifests" -type f -name '*.manifest.json' -print -quit)
MAC_SCRATCH=$MAC_ROOT/capture-scratch
MAC_EVIDENCE=$MAC_ROOT/evidence
PYTHONPATH="$REPO" SWIFTRIGHT_REPO_ROOT="$REPO" "$PYTHON" "$BASE/capture_origin_r11.py" \
  --manifest "$FRESH_MANIFEST" --case-root "$GEN/cases" --scratch "$MAC_SCRATCH" \
  --output "$MAC_EVIDENCE" --runs 20 --expected-host-hash "$HOST_HASH"
```

`capture_origin_r11.py` rebuilds host before launch. If rebuilt bytes differ, it writes `HOST_HASH_DRIFT` and returns before AX preflight/native action. Preserve drift output, choose a new fresh `MAC_ROOT`, rerun host materialization, and use resulting case/manifest/tuple IDs.

After root transports evidence into fresh repo archive, verify exact joins:

```sh
factory/.venv/bin/python factory/oracle/mac/padding-origin-r11-source-v1/verify-r11-output.py \
  --output <fresh-repo-evidence> --case <fresh-case.json> --manifest <fresh-manifest.json>
```

Windows replay consumes only newly materialized case/tuple. Existing r7 executable may pass only exact fresh-case source/witness/compiler closure admission; mismatch requires fresh Windows source-bound compile before Count20. See `WINDOWS-REPLAY-PLAN.md`.
