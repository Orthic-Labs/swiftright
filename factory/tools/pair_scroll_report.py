#!/usr/bin/env python3
"""Scroll gate for a paired Mac/Windows run of a swiftui.scroll case (issue #31). usage: pair_scroll_report.py <case-dir> <runs/<ts> dir>

The pixels of these cases are report-only (a named full-frame exclusion). This gate decides on the scroll readings, per run:
  Mac:     mac-run-NN.log, the MAC_SCROLL lines. The last line whose label starts with "<L>-" is the settled reading of Mac label <L>
           (a scroll op's label is "<L>-to", "<L>-reset", "<L>-wheel", "<L>-ax", "<L>-dv", ...).
  Windows: windows/host-NN.stdout.txt, the WIN_SCROLL lines. The last line with label=in<k> is the settled reading of input k.
<case>/pair.json supplies {"scrollGate": {"pairs": [...], "tolerancePt": 1.0}}, one pair per entry:
  {"mac": "w3", "win": "in1", "perLine": true, "macLines": 3, "winLines": 3}   per-line amount of a wheel input (winLines = lines per input)
  {"mac": "w10", "win": "in10", "clamp": true}                                    both readings at the end of their own range
  {"mac": "omid", "win": "in1"}                                                   drag / scroller: offset and value agree
Rules (tolerancePt in points, value in 0...1):
  - rest = the Mac offset at the case's first label (pair.json phaseShots[0]); the Mac's +0.2 pt List rest offset cancels, and the Mac's
    0.4 pt shorter clip stays inside tolerancePt. Mac offset relative to the rest = mac.offset - rest.
  - a pair whose Mac line has status FAIL or DERIVED (the Mac's paged or end offset was derived, not read from the responder), or whose Mac or
    Windows reading is missing or incomplete, fails closed: a derived value is not a reference.
  - drag pair: |win.offset - (mac.offset - rest)| <= tolerancePt and |win.value - mac.scrollerValue| <= 0.02 (a Mac scrollerValue below 0 is no scroller: fails).
  - perLine pair: the per-line amounts agree over the Mac's line span, |win.offset / winLines - (mac.offset - rest) / macLines| * macLines <= tolerancePt.
    A reading at its own range end (clamped) is no per-line amount: the pair fails.
  - clamp pair: both readings within tolerancePt of their own range end (contentHeight - viewportHeight) and the two range ends agree within tolerancePt.
Pixels are not read here. Writes scroll-report.json into the run directory; exits nonzero on any failure (no runs and no pairs count as failures)."""
import json, math, re, sys
from pathlib import Path

VALUE_TOL = 0.02


def fields(text):
    """key=value tokens of one log line; the first occurrence of a key wins (a trailing free-text note cannot overwrite a field)."""
    d = {}
    for k, v in re.findall(r"(\w+)=(\S+)", text):
        d.setdefault(k, v)
    return d


def number(d, key):
    try:
        v = float(d[key])
    except (KeyError, ValueError):
        return None
    return v if math.isfinite(v) else None


def mac_reading(lines, label):
    """The settled MAC_SCROLL reading of Mac label <label>: the last line of its group ("<label>-...")."""
    hits = [fields(l[len("MAC_SCROLL "):]) for l in lines if l.startswith("MAC_SCROLL ")]
    hits = [d for d in hits if d.get("label", "").startswith(label + "-")]
    if not hits:
        return None
    d = hits[-1]
    return dict(status=d.get("status"), offset=number(d, "offset"), content=number(d, "contentHeight"), view=number(d, "viewportHeight"), value=number(d, "scrollerValue"))


def win_reading(lines, label, upto=False):
    """The settled WIN_SCROLL reading of input <label> (in<k>): the last line printed for that label. With upto (clamp pairs), the last line of
    any input k' <= k: an input that hits the range end changes nothing, so the host prints no new line for it."""
    found = None
    want = int(label[2:]) if upto and label.startswith("in") and label[2:].isdigit() else None
    for l in lines:
        if l.startswith("WIN_SCROLL "):
            d = fields(l[len("WIN_SCROLL "):])
            lab = d.get("label", "")
            if lab == label or (want is not None and lab.startswith("in") and lab[2:].isdigit() and int(lab[2:]) <= want):
                found = d
    if found is None:
        return None
    return dict(status=None, offset=number(found, "offset"), content=number(found, "contentHeight"), view=number(found, "viewportHeight"), value=number(found, "value"))


def judge(pair, m, w, rest, tol):
    """(ok, problems) for one pair; m = Mac reading or None, w = Windows reading or None, rest = Mac offset at the first label or None."""
    tag = f"mac {pair['mac']} / windows {pair['win']}"
    if m is None:
        return False, [f"{tag}: no MAC_SCROLL line for {pair['mac']}"]
    if m["status"] in ("FAIL", "DERIVED"):
        return False, [f"{tag}: mac status {m['status']} (fails closed: a derived value is not a reference)"]
    if w is None:
        return False, [f"{tag}: no WIN_SCROLL line for {pair['win']}"]
    if rest is None:
        return False, [f"{tag}: no Mac reading for the first label (rest offset unknown)"]
    if m["offset"] is None or m["content"] is None or m["view"] is None or w["offset"] is None or w["content"] is None or w["view"] is None:
        return False, [f"{tag}: incomplete reading (offset, contentHeight or viewportHeight missing)"]
    rel, mmax, wmax = m["offset"] - rest, m["content"] - m["view"], w["content"] - w["view"]
    probs = []
    if pair.get("clamp"):
        if abs(rel - mmax) > tol: probs.append(f"{tag}: mac not at its range end (offset {rel:.2f}, end {mmax:.2f})")
        if abs(w["offset"] - wmax) > tol: probs.append(f"{tag}: windows not at its range end (offset {w['offset']:.2f}, end {wmax:.2f})")
        if abs(mmax - wmax) > tol: probs.append(f"{tag}: range ends differ (mac {mmax:.2f}, windows {wmax:.2f})")
    elif pair.get("perLine"):
        ml, wl = float(pair["macLines"]), float(pair["winLines"])
        if abs(rel - mmax) <= tol or abs(w["offset"] - wmax) <= tol:
            probs.append(f"{tag}: a reading is at its range end (mac {rel:.2f}/{mmax:.2f}, windows {w['offset']:.2f}/{wmax:.2f}); no per-line amount")
        diff = abs(w["offset"] / wl - rel / ml) * ml
        if diff > tol: probs.append(f"{tag}: per-line amount differs by {diff:.2f} pt over {ml:g} lines (mac {rel:.2f} pt / {ml:g} lines, windows {w['offset']:.2f} pt / {wl:g} lines)")
    else:
        # A Windows drag moves the thumb in whole device pixels (0.4 pt at scale 2.5): one pixel of thumb travel is maxOffset * 0.4 / travel pt of
        # offset, so the drag target can only be met to within that quantum (the Mac sets its value exactly). Track and thumb as ScrollerMetrics (M1).
        track = w["view"] - 6.2
        thumb = max(20.0, track * w["view"] / w["content"]) if w["content"] > 0 else 20.0
        travel = track - thumb
        quantum = wmax * 0.4 / travel if travel > 0 and wmax > 0 else 0.0
        dtol = tol + quantum
        if abs(w["offset"] - rel) > dtol: probs.append(f"{tag}: offset mac {rel:.2f} windows {w['offset']:.2f} (tolerance {dtol:.2f} pt = {tol:g} + one thumb pixel {quantum:.2f})")
        mval = rel / mmax if mmax > 0 else 0.0      # the Mac value relative to its rest offset (its own scrollerValue counts the 0.2 pt rest)
        if m["value"] is None or m["value"] < 0: probs.append(f"{tag}: mac has no scroller value")
        elif w["value"] is None: probs.append(f"{tag}: windows has no value")
        else:
            vtol = VALUE_TOL + (quantum / wmax if wmax > 0 else 0.0)
            if abs(w["value"] - mval) > vtol: probs.append(f"{tag}: value mac {mval:.3f} windows {w['value']:.3f} (tolerance {vtol:.3f})")
    return not probs, probs


def kind(p):
    return "clamp" if p.get("clamp") else "perLine" if p.get("perLine") else "drag"


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    pj = json.loads((case / "pair.json").read_text())
    cfg = pj["scrollGate"]
    tol = float(cfg.get("tolerancePt", 1.0))
    labels = pj.get("phaseShots") or []
    first = labels[0] if labels else None
    pairs = cfg.get("pairs") or []
    runs = []
    for lg in sorted(out.glob("mac-run-*.log")):
        n = lg.stem.split("-")[-1]
        row = dict(run=int(n), ok=False, problems=[], pairs=[])
        runs.append(row)
        wf = out / "windows" / f"host-{n}.stdout.txt"
        if not wf.is_file():
            row["problems"].append("missing windows/host-NN.stdout.txt"); continue
        mlines = lg.read_text(errors="replace").splitlines()
        wlines = wf.read_text(errors="replace").splitlines()
        rest_m = mac_reading(mlines, first) if first else None
        rest = rest_m["offset"] if rest_m else None
        if not pairs:
            row["problems"].append("scrollGate declares no pairs")
        for p in pairs:
            m, w = mac_reading(mlines, p["mac"]), win_reading(wlines, p["win"], upto=bool(p.get("clamp")))
            ok, probs = judge(p, m, w, rest, tol)
            row["pairs"].append(dict(mac=p["mac"], win=p["win"], kind=kind(p), ok=ok, problems=probs, macReading=m, windowsReading=w))
            row["problems"] += probs
        row["ok"] = not row["problems"]
    passed = sum(1 for r in runs if r["ok"])
    rep = dict(case=case.name, run=out.name, gate=f"scroll readings: per-line / drag / clamp pairs, tolerance {tol:g} pt, value {VALUE_TOL}; pixels report-only",
               tolerancePt=tol, pairs=pairs, runs=len(runs), gatePassed=passed, rows=runs)
    (out / "scroll-report.json").write_text(json.dumps(rep, indent=1))
    print(f"{case.name}: runs={len(runs)} scroll-gate={passed}/{len(runs)} pairs={len(pairs)}")
    for r in runs:
        if not r["ok"]:
            print("  run", r["run"], "; ".join(r["problems"]))
    sys.exit(0 if runs and passed == len(runs) else 1)


if __name__ == "__main__":
    main()
