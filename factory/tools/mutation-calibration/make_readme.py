"""Write README.md: method, layout, how to run, and one row per mutation (generated from the suites, so it cannot drift)."""
import importlib, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from calibrate import SUITES
from report import GATES

HEAD = """# SR1 mutation calibration

Proves that every deciding gate of the SR1 lean loop rejects deliberately seeded faults and still passes near-misses inside its tolerance. This is the queue-open condition in
`docs/sr1-plan.md` ("the gate catches every seeded mutation"). Results: `factory/pipeline/mutation-calibration/results.json` and `RESULTS.md`.

## Method

- **Offline, on existing evidence.** `fixtures.py` copies run 01 of one committed or rerun evidence directory per base (PNG pair, UIA/AX dumps, list dump, host and Mac logs, clock frames) plus the case's own
  `pair.json`, unchanged, into `factory/pipeline/mutation-calibration/fixtures/<base>/` (2.2 MB, no PNG over 100 KB). Nothing is captured; no Windows, Sandbox or Dell is touched.
- **Real code path.** `core.py` stages a fixture in a scratch directory, applies one mutation to the Windows side (capture, UIA JSON or host log) and runs
  `python3 factory/tools/pair.py <case> --recompare <run>` as a subprocess: the same compare-only entry point, gate dispatch (`semantic_gate`, `semantic_decides`) and report generators the pipeline uses.
  `factory/pipeline/consolidation/run_all.py` records that exit status as the case verdict. Exit 0 = the case passes.
- **Kinds.** `catch`: the mutated run must FAIL. `near`: a near-miss placed exactly at or just inside the named tolerance; the run must PASS (otherwise the gate is over-strict). `probe`: a sensitivity sweep, reported only.
  A `catch` that passes is a MISS; if a decision or the comparator's own contract says the property is not gated, the row carries that citation (`design`) and RESULTS.md lists it separately.
- **Baseline first.** Before the summary is written every unmutated fixture must pass; otherwise the run aborts.
- **No thresholds or comparator logic are changed.** Tolerance-edge mutations are derived from each case's own `pair.json` values (for example the label-ink shift that puts the colour difference at exactly 40 and 41).
  Helpers import `pair.edge_band` and the comparators' measuring functions only to pick which pixel to edit; the verdict always comes from the subprocess.
- `s_multirun.py` repeats 20 of the mutations in run 3 of 3 only (runs 1 and 2 untouched), to show a single bad run is not averaged away.

## Run

```
python3 factory/tools/mutation-calibration/fixtures.py     # only to rebuild the fixtures from their sources (read-only on them)
python3 factory/tools/mutation-calibration/calibrate.py    # all mutations -> results.json and RESULTS.md
python3 factory/tools/mutation-calibration/calibrate.py --gate clock --only extent   # a subset (prints, writes nothing)
python3 factory/tools/mutation-calibration/make_readme.py  # regenerate this file
```
A few minutes (about 360 subprocess runs). Python with Pillow (`factory/requirements.txt`); no other dependency.

## Files

`fixtures.py` base evidence table and copier; `core.py` staging and verdict; `mutlib.py` image and JSON helpers; `s_pixel.py`, `s_text.py`, `s_control.py`, `s_semantic.py` (semantic and list),
`s_clock.py`, `s_image.py`, `s_textorigin.py`, `s_multirun.py` the mutation suites; `calibrate.py` runner; `report.py` summary and RESULTS.md.

## Gates

| Gate | Comparator | What decides |
|---|---|---|
"""


def main():
    L = [HEAD]
    for g, (c, d) in GATES.items():
        L.append(f"| {g} | `{c}` | {d} |")
    L.append("\n## Every mutation\n")
    L.append("Base = fixture id (see `fixtures.py` for its case and run). All edits are to the Windows side of run 01 unless the description says otherwise.\n")
    n = 0
    for s in SUITES:
        mods = importlib.import_module(s).MUTATIONS
        if not mods: continue
        cur = None
        for m in mods:
            if m.gate != cur:
                cur = m.gate; L.append(f"\n### {cur}\n\n| Base | Mutation | Kind | What it seeds |\n|---|---|---|---|")
            L.append(f"| {m.base} | `{m.name}` | {m.kind} | {m.what}{' (documented exclusion: ' + m.design + ')' if m.design else ''} |"); n += 1
    L.append(f"\n{n} mutations in total.\n")
    Path(__file__).with_name("README.md").write_text("\n".join(L))
    print(n, "mutations")


if __name__ == "__main__":
    main()
