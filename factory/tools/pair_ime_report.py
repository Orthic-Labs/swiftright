#!/usr/bin/env python3
"""IME marked-text gate for a paired Mac/Windows run of an ime-marked-text case (sr1-decisions #15).

  pair_ime_report.py <case-dir> <run-dir>      -> <run-dir>/ime-report.json, one line per run, exit 0 when every run passes

The accessibility trees carry the composed text only (the semantic gate compares it); the marked range and the selected range live in two logs, so this gate reads both:
  Windows  windows/host-NN.stdout.txt   HOST_FIELD tag=script ... display="abni" selection=4+0 marked=2+2     (one tag=script line after each scripted step: the click and every ime action)
  Mac      mac-run-NN.log               MAC_FACT step=2:ime ... text="abni" selection=4+0 marked=2+2         (one line per click/ime step after `step=start`; the field editor's own state)
Per step (the Nth script line against the Nth MAC_FACT line) and once more for the settled final state (the last HOST_FIELD line against the last MAC_FACT line) it GATES:
  marked     the marked range (location+length, UTF-16 units) is equal; "none" on Windows and an empty range on the Mac (NSTextInputClient leaves {location, 0} after a
             click or a commit) are the same thing: no marked text.
  selection  the selected range (location+length) is equal.
  text       the composed string is equal. The Windows log is written in the console code page, so a non-ASCII character comes out as several unrelated bytes there:
             an all-ASCII Mac string must match exactly; a string with non-ASCII characters must match up to its first non-ASCII character and the Windows string must continue
             beyond it (the exact characters are compared on the final frame by the semantic gate, from UIA values).
A different number of steps, or a missing log or line, fails. Everything else in the logs (committed text, focus, caret x) is reported, not gated here.

Block 40 (swiftui.ime-traps, issue #50) has two TextFields, so the Windows host logs one HOST_FIELD per field per step: the focused field's line (focused=true) is the one compared with the Mac's field editor,
and a field that does not hold the focus must carry no marked range (composition must not leak across a focus change). Optional "imeGate" keys in pair.json:
  "origin": true             also GATE the text origin: originXpx (the x of offset 0 in the focused field, capture px; Mac MAC_FACT originXpx from firstRect, Windows HOST_FIELD originXpx from
                             HostTextInput.caretBounds) must agree within "originTolerancePx" (default 1.0) at every step and at the final state. caretXpx (the caret at the selection start) is REPORTED only:
                             Windows draws the body font at 12 pt and the Mac at 13 pt (decision 2), so an advance-dependent x differs by design. A missing value on either side fails.
  "windowsOnly": {"unchanged": [1, 2]}   for a case whose Mac side cannot take the same steps (imet-badregion-v1: AppKit raises for an invalid range): Windows steps listed must leave the state of step 0
                             untouched (refused), and the final Windows state must equal the final Mac state; no per-step pairing."""
import json, re, sys
from pathlib import Path

WIN_RE = re.compile(r'HOST_FIELD tag=(\S+) id=(\S+) committed="(.*?)" display="(.*?)" selection=(\d+)\+(\d+) marked=(none|\d+\+\d+) focused=(\w+)(?: caretXpx=(-?[\d.]+) originXpx=(-?[\d.]+))?')
MAC_RE = re.compile(r'MAC_FACT step=(\S+) fieldEditor=\d+ text="(.*?)" selection=(\d+)\+(\d+) marked=(?:(\d+)\+(\d+)|none)(?: caretXpx=(-?[\d.]+))?(?: originXpx=(-?[\d.]+))?')


def num(v):
    return None if v is None else float(v)


def marked_range(loc, length):
    return None if length == 0 else [loc, length]


def windows_steps(path):
    """-> (script steps, final) from a host log, or None when the log is missing."""
    if not path.is_file():
        return None
    rows = []
    for m in WIN_RE.finditer(path.read_bytes().decode("latin-1")):
        tag, fid, committed, display, s0, s1, marked, focused, cx, ox = m.groups()
        mk = None if marked == "none" else marked_range(*(int(v) for v in marked.split("+")))
        rows.append(dict(tag=tag, id=fid, committed=committed, text=display, selection=[int(s0), int(s1)], marked=mk, focused=focused == "true", caretX=num(cx), originX=num(ox)))
    script = [r for r in rows if r["tag"] == "script"]
    nfields = len({r["id"] for r in script}) or 1
    if len(script) % nfields:
        return [], None, [f"windows script lines {len(script)} are not a multiple of the {nfields} fields"]
    steps, leaks = [], []
    for k in range(0, len(script), nfields):
        chunk = script[k:k + nfields]
        focused = [r for r in chunk if r["focused"]]
        if len(focused) != 1:
            return [], None, [f"windows step {k // nfields}: {len(focused)} focused fields, expected 1"]
        steps.append(focused[0])
        leaks += [f"windows step {k // nfields}: unfocused field {r['id']} holds marked range {r['marked']}" for r in chunk if not r["focused"] and r["marked"] is not None]
    return steps, (steps[-1] if steps else None), leaks


def mac_steps(path):
    """-> (steps, final) from a Mac run log: the MAC_FACT lines after step=start."""
    if not path.is_file():
        return None
    rows = []
    for m in MAC_RE.finditer(path.read_text(encoding="utf-8", errors="replace")):
        step, text, s0, s1, m0, m1, cx, ox = m.groups()
        rows.append(dict(step=step, text=text, selection=[int(s0), int(s1)], marked=marked_range(int(m0 or 0), int(m1 or 0)), caretX=num(cx), originX=num(ox)))
    return rows, (rows[-1] if rows else None)


def text_equal(mac, win):
    """exact for an all-ASCII Mac string; otherwise equal up to the first non-ASCII character, with the Windows string continuing beyond it"""
    if mac.isascii():
        return mac == win
    prefix = mac[:next(i for i, c in enumerate(mac) if not c.isascii())]
    return win.startswith(prefix) and len(win) > len(prefix)


def origin_mismatches(label, mac, win, tol):
    if mac.get("originX") is None or win.get("originX") is None:
        return [f"{label}: originXpx missing (mac {mac.get('originX')}, windows {win.get('originX')})"]
    if abs(mac["originX"] - win["originX"]) > tol:
        return [f"{label}: text origin x mac {mac['originX']} != windows {win['originX']} (tolerance {tol} px)"]
    return []


def step_mismatches(label, mac, win, tol=None):
    why = []
    if tol is not None:
        why += origin_mismatches(label, mac, win, tol)
    if mac["marked"] != win["marked"]:
        why.append(f"{label}: marked range mac {mac['marked']} != windows {win['marked']}")
    if mac["selection"] != win["selection"]:
        why.append(f"{label}: selection mac {mac['selection']} != windows {win['selection']}")
    if not text_equal(mac["text"], win["text"]):
        why.append(f"{label}: composed text mac {mac['text']!r} != windows {win['text']!r}")
    return why


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text()).get("imeGate", {})
    tol = float(cfg.get("originTolerancePx", 1.0)) if cfg.get("origin") else None
    win_only = cfg.get("windowsOnly")
    rows = []
    for macpng in sorted((out / "mac").glob("run-[0-9][0-9].png")):
        n = macpng.stem.split("-")[1]
        w, m = windows_steps(out / f"windows/host-{n}.stdout.txt"), mac_steps(out / f"mac-run-{n}.log")
        why, steps = [], []
        if w is None or m is None:
            why.append(f"missing log: windows host log {'present' if w else 'MISSING'}, mac run log {'present' if m else 'MISSING'}")
        else:
            wsteps, wfinal, wnotes = w
            why += wnotes
            msteps = [r for r in m[0] if r["step"] != "start"]
            if win_only:
                if not wsteps or not msteps:
                    why.append("windows-only case: missing windows steps or mac final state")
                else:
                    base = wsteps[0]
                    for k in win_only.get("unchanged", []):
                        if k >= len(wsteps):
                            why.append(f"step {k}: no windows script line")
                        elif any(wsteps[k][f] != base[f] for f in ("text", "selection", "marked")):
                            why.append(f"step {k}: windows state changed by a refused range ({base['text']!r} {base['selection']} {base['marked']} -> {wsteps[k]['text']!r} {wsteps[k]['selection']} {wsteps[k]['marked']})")
                    why += step_mismatches("final state", msteps[-1], wsteps[-1], tol)
                rows.append(dict(run=int(n), ok=not why, why=why, steps=[]))
                continue
            if not msteps or len(wsteps) != len(msteps):
                why.append(f"step count: windows script steps {len(wsteps)}, mac MAC_FACT steps {len(msteps)}")
            for k, (ms, ws) in enumerate(zip(msteps, wsteps)):
                bad = step_mismatches(f"step {k} ({ms['step']})", ms, ws, tol)
                steps.append(dict(step=ms["step"], mac=dict(text=ms["text"], selection=ms["selection"], marked=ms["marked"], caretX=ms["caretX"], originX=ms["originX"]),
                                  windows=dict(text=ws["text"], selection=ws["selection"], marked=ws["marked"], caretX=ws["caretX"], originX=ws["originX"]), ok=not bad))
                why += bad
            if msteps and wfinal:
                why += step_mismatches("final state", msteps[-1], wfinal, tol)
            elif msteps:
                why.append("final state: no HOST_FIELD line in the windows host log")
        rows.append(dict(run=int(n), ok=not why, why=why, steps=steps))
    bad = sum(1 for r in rows if not r["ok"])
    rep = dict(gate="ime marked range, selected range and composed text per step", pairs=len(rows), fail=bad, rows=rows)
    (out / "ime-report.json").write_text(json.dumps(rep, indent=1, ensure_ascii=True))
    for r in rows[:1] + [r for r in rows[1:] if not r["ok"]]:
        print(f"  ime run {r['run']:02d} {'ok' if r['ok'] else 'FAIL ' + '; '.join(r['why'])[:400]} steps={[(s['step'], s['mac']['marked'], s['mac']['selection']) for s in r['steps']]}")
    print(f"ime pairs={len(rows)} pass={len(rows) - bad} fail={bad}")
    sys.exit(1 if bad or not rows else 0)


if __name__ == "__main__":
    main()
