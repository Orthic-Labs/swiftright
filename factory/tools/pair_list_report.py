#!/usr/bin/env python3
"""List gate for a paired Mac/Windows run of a List (block 16). usage: pair_list_report.py <case-dir> <runs/<ts> dir>

The pixels are gated by pair.py (exact or edge-aa 32 outside the named row-label regions, decision 2). This tool gates what pixels cannot say, per run:
 1. the rows: the Mac table's rows (mac/list-NN.json, written by the Mac host from its NSOutlineView: index, selected, text, frame) against the Windows
    UI Automation list items (windows/uia-NN.json, the host's `list` and `list item` nodes): the same number of rows, the same text in the same order,
    the same selected flag, and the same frame within `rowTolerancePx` (x, y, width, height in client pixels);
 2. the row label ink: the ink colour of every row's label region (the pixel farthest from the row's own background) within `textColourTolerance` per channel
    of the Mac's (white on an accent selection, the primary label colour elsewhere);
 3. optionally `rowHeights` (px): every row's height equals the listed one.
<case>/pair.json supplies {"listGate": {"rowsTopPx": 125, "rowHeightPx": 60, "listRect": [x0, y0, x1, y1], "rows": N, "textColourTolerance": 40, "rowTolerancePx": 1}}.
It REPORTS, never gates: the keyboard flag of the Mac table and the Windows list's own bounds."""
import json, sys
from pathlib import Path
from PIL import Image


def flatten(node, out):
    out.append(node)
    for c in node.get("children") or []:
        flatten(c, out)
    return out


def windows_rows(doc):
    """(list bounds, rows) from the main window's UIA tree; rows in client pixels."""
    main = next((w for w in doc.get("windows", []) if w.get("main")), None)
    if not main or "tree" not in main: return None, []
    cx, cy = main["client"][0], main["client"][1]
    nodes = flatten(main["tree"], [])
    lists = [n for n in nodes if n.get("role") == "List"]
    if not lists: return None, []
    lst = lists[0]
    def rel(b): return None if not b else [round(b[0] - cx, 1), round(b[1] - cy, 1), b[2], b[3]]
    rows = []
    for n in flatten(lst, []):
        if n is lst or n.get("role") != "ListItem": continue
        rows.append(dict(text=n.get("name") or "", selected=bool(n.get("selected")), frame=rel(n.get("bounds"))))
    return rel(lst.get("bounds")), rows


def label_ink(img, rect, bg):
    best, bp = -1, None
    for p in img.crop(rect).getdata():
        d = sum(abs(a - b) for a, b in zip(p, bg))
        if d > best: best, bp = d, p
    return None if best <= 0 else list(bp)


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["listGate"]
    top, rh, rows_expected = int(cfg["rowsTopPx"]), int(cfg["rowHeightPx"]), cfg.get("rows")
    ttol, rtol, heights = int(cfg.get("textColourTolerance", 40)), float(cfg.get("rowTolerancePx", 1)), cfg.get("rowHeights")
    S = 2.5
    results = []
    for mac in sorted((out / "mac").glob("run-*.png")):
        n = mac.stem.split("-")[1]
        row = dict(run=int(n), ok=False)
        results.append(row)
        mj, uj, win = out / "mac" / f"list-{n}.json", out / "windows" / f"uia-{n}.json", out / "windows" / f"native-{n}.png"
        if not mj.is_file() or not uj.is_file() or not win.is_file(): row["error"] = "missing mac list dump, windows uia dump or windows capture"; continue
        mdoc, udoc = json.loads(mj.read_text()), json.loads(uj.read_text(encoding="utf-8-sig"))
        lb, wrows = windows_rows(udoc)
        mrows = [dict(text=r["text"], selected=r["selected"], frame=[round(v * S, 1) for v in r["frame"]]) for r in mdoc["rows"]]
        problems = []
        if rows_expected is not None and len(mrows) != rows_expected: problems.append(f"mac has {len(mrows)} rows, expected {rows_expected}")
        if len(wrows) != len(mrows): problems.append(f"row count mac={len(mrows)} windows={len(wrows)}")
        for i, (m, w) in enumerate(zip(mrows, wrows)):
            if m["text"] != w["text"]: problems.append(f"row {i} text mac={m['text']!r} windows={w['text']!r}")
            if m["selected"] != w["selected"]: problems.append(f"row {i} selected mac={m['selected']} windows={w['selected']}")
            if w["frame"] is None or any(abs(a - b) > rtol for a, b in zip(m["frame"], w["frame"])): problems.append(f"row {i} frame mac={m['frame']} windows={w['frame']}")
            if heights and abs(w["frame"][3] - heights[i]) > rtol: problems.append(f"row {i} height {w['frame'][3]} != {heights[i]}")
        # label ink per row
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        ink = []
        x0 = int(cfg["listRect"][0]) + (20 if "plain" in case.name else 40)
        for i, m in enumerate(mrows):
            y, h = int(round(m["frame"][1])), int(round(m["frame"][3]))
            rect = (x0, y + h // 5, x0 + 150, y + h - h // 5)
            bg_m, bg_w = im.getpixel((int(cfg["listRect"][2]) - 30, y + h // 2)), iw.getpixel((int(cfg["listRect"][2]) - 30, y + h // 2))
            a, b = label_ink(im, rect, bg_m), label_ink(iw, rect, bg_w)
            good = a is not None and b is not None and all(abs(p - q) <= ttol for p, q in zip(a, b))
            ink.append(dict(row=i, mac=a, windows=b, ok=good))
            if not good: problems.append(f"row {i} label ink mac={a} windows={b}")
        row.update(ok=not problems, problems=problems, rows=dict(mac=mrows, windows=wrows), labelInk=ink, macKeyboard=mdoc.get("keyboard"), windowsListBounds=lb)
    ok = sum(1 for r in results if r.get("ok"))
    rep = dict(case=case.name, run=out.name, pairs=len(results), gatePassed=ok, gate="rows (count, text, order, selected, frame within %s px) and label ink within %d per channel; pixels by pair.py" % (rtol, ttol), rows=results)
    (out / "list-report.json").write_text(json.dumps(rep, indent=1))
    print(f"{case.name}: pairs={len(results)} list-gate={ok}/{len(results)}")
    for r in results:
        if not r.get("ok"): print("  run", r["run"], (r.get("error") or r.get("problems")))
    sys.exit(0 if results and ok == len(results) else 1)


if __name__ == "__main__":
    main()
