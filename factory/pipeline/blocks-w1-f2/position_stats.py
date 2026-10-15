#!/usr/bin/env python3
"""Per-row position tolerances for system-font text (F2, and block 28 which it supersedes; Oracle blocking finding on block 28; decision G71).

Windows minus Mac, per region and run, in capture pixels (scale 2.5): first ink y (dy), baseline (db), ink mid-point (dc = (dy+db)/2), first ink column (dx).
A row is keyed by its canonical font (design, size, weight, suffix): "Font.system(size: 13, weight: .regular)", "13pt regular" and "Font.system(size: 13)" are one key.

Method (the I2 method, split by capture set, not by hand):
  FIT set   = F2 captures (stage fc4a39a89, renderer 0.8, N=20), runs 1-10 of every F2 case. Tolerance per key = ceil(max |delta|) per metric (dc to the next half).
  GATE set  = F2 runs 11-20 (the same cases, the other runs) and the block 28 captures on the same stage and renderer (9 cases, 3 runs each: other witnesses, other text).
              A key with no fitted tolerance is UNFITTED: its rows are gated at 0 px (fail closed, pair_textcolour_report.py:62), never given a blanket value.
Nothing is tuned on the GATE set. The case-level blanket tolerances are removed from pair.json; each region carries its own "position" tolerances.

  position_stats.py --write        fit on the FIT set; write per-region tolerances into every F2 and block 28 pair.json (regions of unfitted keys get none)
  position_stats.py --recompare    judge the GATE set against the pair.json tolerances (no capture); prints the verdict per case, writes gate-verdicts.json
  position_stats.py --summary      the delta table of the FIT set and GATE set (read only)
"""
import argparse, glob, json, math, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PIPE = HERE.parent
F2 = HERE / "swiftui.system-font-f2"
B28 = PIPE / "blocks-26-34" / "swiftui.system-font"
STAGE, RENDERER = "fc4a39a89-f623e43e", "renderer-0.8-fc4a39a8"
FIT_MAX_RUN = 10
METRICS = ("dy", "db", "dc", "dx")
TOLKEY = {"dy": "firstInkYTolerancePx", "db": "baselineTolerancePx", "dc": "inkCentreYTolerancePx", "dx": "firstInkXTolerancePx"}


def canon(expr):
    """canonical font key from a region name or a witness expression"""
    s = re.sub(r"\s+", "", expr)
    m = re.fullmatch(r"(?:Font)?\.system\(size:([\d.]+)(?:,weight:\.(\w+))?(?:,design:\.(\w+))?\)(.*)", s)
    if m:
        return f"system|size={float(m[1]):g}|weight={m[2] or 'regular'}|design={m[3] or 'default'}|{m[4]}"
    m = re.fullmatch(r"(\d+(?:\.\d+)?)pt(\w+)", s)
    if m:
        return f"system|size={float(m[1]):g}|weight={m[2]}|design=default|"
    m = re.fullmatch(r"(?:Font)?\.(\w+)((?:\.\w+\([^)]*\))*)", s)
    if m:
        mods = m[2].replace(".weight(.bold)", ".bold()")   # the emphasized weight: Font.x.bold() and Font.x.weight(.bold) are one font
        return f"style={m[1]}|{mods}"
    raise ValueError(f"unrecognised font expression: {expr}")


def region_key(name):
    return canon(re.sub(r"^row \d+ (item \d+ )?", "", name))


def witness_keys(case):
    """the .font(...) expressions of the witness, in source order (block 28 rows are the Text lines in order)"""
    src = (case / "mac-source/Sources/MacHost/Witness.swift").read_text()
    keys, i = [], 0
    while True:
        i = src.find(".font(", i)
        if i < 0: break
        j, depth = i + len(".font("), 1
        while depth:
            depth += {"(": 1, ")": -1}.get(src[j], 0); j += 1
        keys.append(canon(src[i + len(".font("):j - 1])); i = j
    return keys


def final_report(case):
    """the latest run dir of the case on the stage and renderer, with its text-colour report"""
    best = None
    for rp in sorted(glob.glob(str(case / "runs/*/text-colour-report.json"))):
        bp = Path(rp).parent / "build.json"
        if not bp.is_file(): continue
        b = json.loads(bp.read_text())
        if (b.get("stage") or {}).get("name") == STAGE and RENDERER in ((b.get("renderer") or {}).get("path") or ""):
            best = Path(rp)
    return best


def observations(case, report, keys):
    out = []
    rep = json.loads(report.read_text())
    for row in rep["rows"]:
        for j, reg in enumerate(row["regions"]):
            p = reg.get("position")
            if not p or not p.get("mac") or not p.get("windows"): continue
            m, w = p["mac"], p["windows"]
            dy, db = w["firstInkY"] - m["firstInkY"], w["baselineY"] - m["baselineY"]
            out.append(dict(case=case.name, run=row["run"], region=j, key=keys[j], dy=dy, db=db, dc=(dy + db) / 2, dx=w["firstInkX"] - m["firstInkX"]))
    return out


def load_sets():
    fit, gate, cases = [], [], {}
    res = [json.loads(l) for l in (HERE / "results.jsonl").read_text().splitlines() if l.strip()]
    f2_latest = {}
    for r in res:
        if r["stage"] == STAGE and r["renderer"] == "r08final" and r["n"] == 20 and r.get("out"): f2_latest[r["case"]] = r
    for case_rel in sorted(f2_latest):
        case = PIPE / case_rel
        rp = Path(f2_latest[case_rel]["out"]) / "text-colour-report.json"
        if not rp.is_file(): continue
        pj = json.loads((case / "pair.json").read_text())
        keys = [region_key(r["name"]) for r in pj["textColourGate"]["regions"]]
        obs = observations(case, rp, keys)
        cases[case.name] = dict(set="F2", report=str(rp), keys=keys, path=case / "pair.json")
        fit += [o for o in obs if o["run"] <= FIT_MAX_RUN]
        gate += [o for o in obs if o["run"] > FIT_MAX_RUN]
    for case in sorted(B28.glob("*")):
        if not (case / "pair.json").is_file(): continue
        rp = final_report(case)
        if rp is None: continue
        keys = witness_keys(case)
        pj = json.loads((case / "pair.json").read_text())
        if len(keys) != len(pj["textColourGate"]["regions"]): raise SystemExit(f"{case.name}: {len(keys)} font expressions, {len(pj['textColourGate']['regions'])} regions")
        obs = observations(case, rp, keys)
        cases[case.name] = dict(set="B28", report=str(rp), keys=keys, path=case / "pair.json")
        gate += obs
    return fit, gate, cases


def fit_table(fit):
    table = {}
    for o in fit:
        t = table.setdefault(o["key"], {m: 0.0 for m in METRICS})
        for m in METRICS: t[m] = max(t[m], abs(o[m]))
    out = {}
    for k, t in table.items():
        out[k] = dict(firstInkYTolerancePx=math.ceil(t["dy"]), baselineTolerancePx=math.ceil(t["db"]), inkCentreYTolerancePx=math.ceil(t["dc"] * 2) / 2, firstInkXTolerancePx=math.ceil(t["dx"]))
    return out


def judge(o, tol):
    """the comparator's rule: a region without tolerances gets 0 (fail closed); an unfitted row is reported as UNFITTED"""
    if tol is None:
        tol = {v: 0 for v in TOLKEY.values()}; prefix = "UNFITTED:"
    else:
        prefix = ""
    why = []
    for m in METRICS:
        if abs(o[m]) > tol[TOLKEY[m]] + 1e-9: why.append(f"{m} {o[m]:+g} (tol {tol[TOLKEY[m]]:g})")
    return prefix + ";".join(why) if why else ("UNFITTED-but-zero-delta" if prefix else "ok")


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--write", action="store_true"); ap.add_argument("--recompare", action="store_true"); ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    fit, gate, cases = load_sets()
    table = fit_table(fit)
    if a.summary or not (a.write or a.recompare):
        for name, grp in (("FIT (F2 runs 1-10)", fit), ("GATE (F2 runs 11-20 and block 28)", gate)):
            print(name, len(grp), "observations")
            for k in sorted({o["key"] for o in grp}):
                rows = [o for o in grp if o["key"] == k]
                print(f"  {k:60s} n={len(rows):3d} " + " ".join(f"{m} {min(r[m] for r in rows):+g}..{max(r[m] for r in rows):+g}" for m in METRICS))
    if a.write:
        for name, c in cases.items():
            pj = json.loads(c["path"].read_text()); tg = pj["textColourGate"]
            base = {k: v for k, v in tg.get("position", {}).items() if k not in TOLKEY.values()}
            unfit = 0
            for j, reg in enumerate(tg["regions"]):
                reg.pop("position", None)
                tol = table.get(c["keys"][j])
                if tol is None: unfit += 1; continue
                reg["position"] = dict(tol, reason=f"per-row fit (decision G71): {c['keys'][j]}, FIT set F2 runs 1-10 (stage {STAGE}, renderer 0.8)")
            base["reason"] = ("per-row tolerances (decision G71): each region carries its own tolerances fitted on the F2 FIT set (runs 1-10, stage " + STAGE + ", renderer 0.8); "
                              "unfitted rows carry none and are gated at 0 px (fail closed, pair_textcolour_report.py:62). The case-level tolerances were removed (they were one blanket set fitted on the judged runs).")
            tg["position"] = dict(base, align=tg.get("position", {}).get("align", "leading"))
            c["path"].write_text(json.dumps(pj, indent=1) + "\n")
            print(f"{name}: {len(tg['regions']) - unfit} regions with per-row tolerances, {unfit} unfitted")
        (HERE / "row-tolerances.json").write_text(json.dumps(dict(stage=STAGE, renderer=RENDERER, fitRuns=f"1-{FIT_MAX_RUN}", table=table), indent=1) + "\n")
        print("row-tolerances.json written:", len(table), "keys")
    if a.recompare:
        verdicts = {}
        for o in gate:
            c = cases[o["case"]]
            pj = json.loads(c["path"].read_text())
            r = pj["textColourGate"]["regions"][o["region"]]
            tol = r.get("position")
            verdicts.setdefault(o["case"], {}).setdefault(o["run"], []).append(judge(o, tol))
        out = {}
        for case, runs in sorted(verdicts.items()):
            ok_runs = sum(1 for rr in runs.values() if all(v == "ok" for v in rr))
            fails = sorted({f"{k}: {v}" for rr in runs.values() for k, v in [(None, x) for x in rr] if v not in ("ok",)})[:6]
            unf = sorted({o["key"] for o in gate if o["case"] == case and table.get(o["key"]) is None})
            out[case] = dict(runs=len(runs), passingRuns=ok_runs, unfittedKeys=unf, failures=fails)
            print(f"{case}: {ok_runs}/{len(runs)} runs pass" + (f"; unfitted {unf}" if unf else "") + ("" if not fails else "; " + " | ".join(fails[:3])))
        (HERE / "gate-verdicts.json").write_text(json.dumps(out, indent=1) + "\n")


main()
