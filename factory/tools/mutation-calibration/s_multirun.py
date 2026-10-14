"""Aggregation over N runs: the pipeline verdict is 'every run passes'. Clone run 01 to runs 02 and 03, apply a mutation from another suite to run 03 ONLY, and require the
case to fail (catch) or pass (near-miss). Shows a single bad run among N is not averaged away."""
import re, shutil
from core import M

MUTATIONS = []
import s_pixel, s_text, s_control, s_semantic, s_clock, s_textorigin
POOL = {(m.gate, m.base, m.name): m for mod in (s_pixel, s_text, s_control, s_semantic, s_clock, s_textorigin) for m in mod.MUTATIONS}


def renumber(name, n): return re.sub(r"-01(?=[-.])", f"-{n:02d}", name)


def third_only(inner):
    def f(ctx):
        files = [p for p in ctx.run.rglob("*") if p.is_file() and re.search(r"-01(?=[-.])", p.name)]
        for p in files:                                   # pristine copies as runs 02 and 03
            for n in (2, 3):
                shutil.copy2(p, p.with_name(renumber(p.name, n)))
        desc = inner(ctx)                                 # mutates run 01's files
        for p in files:                                   # mutated 01 -> 03, pristine 02 back to 01
            if p.exists():
                shutil.move(str(p), str(p.with_name(renumber(p.name, 3))))
            shutil.copy2(p.with_name(renumber(p.name, 2)), p)
        return desc + " (applied to run 3 of 3; runs 1 and 2 untouched)"
    return f


PICKS = [("pixel", "px-exact", "shift-1px", "catch"), ("pixel", "px-edge", "band+32", "near"), ("pixel", "px-edge", "band+33", "catch"),
         ("button", "btn-bordered", "y-shift-1px", "catch"), ("button", "btn-bordered", "label-ink-at-tolerance", "near"), ("button", "btn-bordered", "label-ink-just-beyond", "catch"),
         ("control", "ctl-switch", "label-centre-near", "near"), ("control", "ctl-switch", "label-centre-beyond", "catch"),
         ("list", "list-arrow", "row-order", "catch"), ("list", "list-arrow", "row-frame-y-at-tolerance", "near"), ("list", "list-arrow", "selection-moved", "catch"),
         ("semantic", "sem-click", "wrong-value", "catch"), ("semantic", "sem-click", "name-whitespace", "near"),
         ("clock", "clk-linear", "extent+beyond", "catch"), ("clock", "clk-linear", "extent+near", "near"), ("clock", "clk-linear", "timing-progress-beyond", "catch"),
         ("text-origin", "to-filled", "origin-1px", "catch"), ("text-origin", "to-filled", "right-clip-differs", "near"),
         ("text-colour", "tc-red", "r0-ink-just-beyond", "catch"), ("text-colour", "tc-red", "r0-ink-at-tolerance", "near")]
for gate, base, name, kind in PICKS:
    m = POOL[(gate, base, name)]
    MUTATIONS.append(M("multi-run", base, f"{gate}/{name}@run3of3", kind, third_only(m.fn), f"{m.what} in 1 of 3 runs"))
