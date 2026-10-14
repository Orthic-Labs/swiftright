#!/usr/bin/env python3
"""Text-origin gate for a paired Mac/Windows run of a bezeled TextField case (sr1-decisions #12).

  pair_textorigin_report.py <case-dir> <run-dir>     -> <run-dir>/textorigin-report.json, one line per (run, field), exit 0 when every one passes

Glyph shapes stay excluded (decision 2: Segoe UI vs SF), but WHERE the text starts is gated, on the final frame of every run, for each field rect:
  1. first ink x: the leftmost column holding a pixel more than 32/255 darker than the darkest background colour present (the field fill, and the selection
     highlight when one is drawn: the AA band of decision 5), caret columns removed. Mac and Windows must agree within "firstInkTolerancePx" (default 0).
     A non-zero tolerance is a named, measured value in pair.json with its reason ("firstInkToleranceReason"), never a default.
  2. selection: present on one side and not the other fails. When both draw one: the colour must be identical (the Mac's NSColor.selectedTextBackgroundColor
     over white, (179,215,255)) and the start x (the leftmost column of >= 10 pixels of that exact colour) must be equal within "selectionStartTolerancePx"
     (default 0). The selection's end x and height follow the glyph advances and the line height (Segoe vs SF) and are reported, not gated.
  3. caret: the Mac draws no caret in a window that is never on a display, so its insertion point is read from the field editor (MAC_FACT caretXpx in
     mac-run-NN.log: firstRect of an empty range at the selection, capture px). With "caret": "macFact" the leftmost column of the Windows caret (a 1-2 px column in the
     exact caret colour 0x111111) must equal it within "caretTolerancePx" (default 0), for a caret at the text origin (an empty focused field: no glyph advance in it).
     Without "caret" the Windows caret column is reported only.
  4. clip edge (opt-in, "lastInk": true, for a field whose text is clipped): the rightmost ink column. A glyph cut by the clip edge ends exactly on it, so the two sides
     must agree within "lastInkTolerancePx" (default 0): this is the right-hand twin of the origin (the same 6 pt inset).
pair.json:  "textOriginGate": {"fields": [[x0,y0,x1,y1], ...]   // field FRAMES in capture px (the 1 pt border is drawn outside them)
                               "firstInkTolerancePx": 0, "firstInkToleranceReason": "...", "selectionStartTolerancePx": 0, "requireInk": true,
                               "caret": "macFact", "caretTolerancePx": 0, "lastInk": true}"""
import json, re, sys
from collections import Counter
from pathlib import Path
from PIL import Image

CARET = (17, 17, 17)
INK_MARGIN = 32          # decision 5: 32/255 anti-aliasing band


def lum(p):
    return (299 * p[0] + 587 * p[1] + 114 * p[2]) / 1000


def analyse(im, frame):
    x0, y0, x1, y1 = frame
    # the interior without the rounded corners: 2 px in from the sides, 10 px in from the top and bottom (corner radius 15 px)
    rx0, ry0, rx1, ry1 = x0 + 2, y0 + 10, x1 - 2, y1 - 10
    px = im.load()
    pts = [(x, y, px[x, y]) for y in range(ry0, ry1) for x in range(rx0, rx1)]
    bg = Counter(p for _, _, p in pts).most_common(1)[0][0]
    # selection highlight: saturated light blue (the colour itself is gated, so detect by hue, not value)
    sel_px = [(x, y, p) for x, y, p in pts if p[2] >= 230 and p[2] - p[0] >= 50 and p[0] <= 200]
    sel = None
    if len(sel_px) >= 50:
        colour = Counter(p for _, _, p in sel_px).most_common(1)[0][0]
        cols = Counter(x for x, _, p in sel_px if p == colour)
        full = sorted(x for x, n in cols.items() if n >= 10)
        if full:
            xs = [x for x, _, p in sel_px if p == colour]
            ys = [y for _, y, p in sel_px if p == colour]
            sel = dict(colour=list(colour), startX=full[0], endX=max(full), y0=min(ys), y1=max(ys) + 1, pixels=len(xs))
    # caret columns (exact caret colour, tall): reported, removed from the ink
    caret_cols = Counter(x for x, _, p in pts if p == CARET)
    caret_x = sorted(x for x, n in caret_cols.items() if n >= 18)
    thr = min([lum(bg)] + ([lum(tuple(sel["colour"]))] if sel else [])) - INK_MARGIN
    ink = [x for x, _, p in pts if lum(p) <= thr and x not in caret_x]
    return dict(background=list(bg), firstInkX=min(ink) if ink else None, lastInkX=max(ink) if ink else None, selection=sel, caretX=caret_x or None)


def gate(mac, win, cfg):
    tol_ink = int(cfg.get("firstInkTolerancePx", 0))
    tol_sel = int(cfg.get("selectionStartTolerancePx", 0))
    why = []
    if mac["firstInkX"] is None or win["firstInkX"] is None:
        if cfg.get("requireInk", True) or (mac["firstInkX"] is None) != (win["firstInkX"] is None):
            why.append(f"no ink: mac={mac['firstInkX']} win={win['firstInkX']}")
    else:
        d = win["firstInkX"] - mac["firstInkX"]
        if abs(d) > tol_ink:
            why.append(f"first ink x differs by {d} px (mac {mac['firstInkX']}, win {win['firstInkX']}, tolerance {tol_ink})")
    if cfg.get("lastInk") and mac["lastInkX"] is not None and win["lastInkX"] is not None:
        d = win["lastInkX"] - mac["lastInkX"]
        if abs(d) > int(cfg.get("lastInkTolerancePx", 0)):
            why.append(f"last ink x (clip edge) differs by {d} px (mac {mac['lastInkX']}, win {win['lastInkX']})")
    ms, ws = mac["selection"], win["selection"]
    if (ms is None) != (ws is None):
        why.append(f"selection drawn on {'mac' if ms else 'windows'} only")
    elif ms:
        if ms["colour"] != ws["colour"]:
            why.append(f"selection colour mac {tuple(ms['colour'])} != windows {tuple(ws['colour'])}")
        if abs(ms["startX"] - ws["startX"]) > tol_sel:
            why.append(f"selection start x mac {ms['startX']} != windows {ws['startX']} (tolerance {tol_sel})")
    return why


def mac_caret_px(out, n):
    """The last MAC_FACT caretXpx of mac-run-NN.log (the insertion point after the final step), or None."""
    log = out / f"mac-run-{n}.log"
    vals = [float(m) for m in re.findall(r"MAC_FACT .*? caretXpx=([0-9.\-]+)", log.read_text(errors="replace"))] if log.is_file() else []
    return vals[-1] if vals else None


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["textOriginGate"]
    rows, bad = [], 0
    for mac_png in sorted((out / "mac").glob("run-[0-9][0-9].png")):
        n = mac_png.stem.split("-")[1]
        win_png = out / "windows" / f"native-{n}.png"
        if not win_png.is_file():
            rows.append(dict(run=int(n), ok=False, why=["missing windows capture"])); bad += 1; continue
        im, iw = Image.open(mac_png).convert("RGB"), Image.open(win_png).convert("RGB")
        for k, frame in enumerate(cfg["fields"]):
            m, w = analyse(im, frame), analyse(iw, frame)
            why = gate(m, w, cfg)
            if k == 0 and cfg.get("caret") == "macFact":
                mc, wc = mac_caret_px(out, n), (w["caretX"] or [None])[0]
                m["caretXpx"] = mc
                if mc is None or wc is None:
                    why.append(f"caret: mac insertion point {mc}, windows caret column {wc}")
                elif abs(wc - mc) > float(cfg.get("caretTolerancePx", 0)):
                    why.append(f"caret x mac {mc:.2f} != windows column {wc} (tolerance {cfg.get('caretTolerancePx', 0)} px)")
            rows.append(dict(run=int(n), field=k, frame=frame, ok=not why, why=why, mac=m, windows=w))
            bad += bool(why)
    rep = dict(gate="text origin (first ink x, selection colour and start x)", firstInkTolerancePx=cfg.get("firstInkTolerancePx", 0),
               firstInkToleranceReason=cfg.get("firstInkToleranceReason"), selectionStartTolerancePx=cfg.get("selectionStartTolerancePx", 0),
               checks=len(rows), fail=bad, rows=rows)
    (out / "textorigin-report.json").write_text(json.dumps(rep, indent=1))
    for r in rows[:3] + [r for r in rows[3:] if not r["ok"]]:
        if "mac" not in r:
            print(f"  textorigin run {r['run']:02d}: FAIL {r['why']}"); continue
        m, w = r["mac"], r["windows"]
        sm, sw = m["selection"], w["selection"]
        print(f"  textorigin run {r['run']:02d} field {r['field']}: {'ok' if r['ok'] else 'FAIL ' + '; '.join(r['why'])} first-ink mac={m['firstInkX']} win={w['firstInkX']}"
              + (f" selection mac x={sm['startX']} {tuple(sm['colour'])} win x={sw['startX']} {tuple(sw['colour'])}" if sm and sw else "") + (f" caret win x={w['caretX']}" if w["caretX"] else "") + (f" caret mac insertion x={m['caretXpx']}" if m.get("caretXpx") is not None else ""))
    d = Counter((r["windows"]["firstInkX"] - r["mac"]["firstInkX"]) for r in rows if "mac" in r and r["mac"]["firstInkX"] is not None and r["windows"]["firstInkX"] is not None)
    print(f"textorigin checks={len(rows)} pass={len(rows) - bad} fail={bad} first-ink delta (win-mac px): {dict(sorted(d.items()))}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
