#!/usr/bin/env python3
"""F3 semantic comparator: Windows UI Automation dump (F2: windows/uia-NN.json) against the Mac in-process accessibility dump (mac/ax-NN.json, written by the
Mac capture host with factory/tools/mac-ax-dump/AXDump.swift; no AX API across processes, no TCC prompt).

  pair_semantic_report.py <case-dir> <run-dir>      -> <run-dir>/semantic-report.json, one line per run, exit 0 when every run passes

The gate comes from <case>/pair.json "semanticGate":
  {
    "fields":   ["role","name","toggle","enabled","focus","value","bounds","order","count","range","help","heading","link"],   // help: UIA FullDescription (hint -> AccessKit description) = AXHelp; heading: UIA localized type "heading" or Level > 0 = AXHeading; link: UIA Hyperlink = AXLink (ABI 0.13 extras)   // "range": slider RangeValue (value, min, max; with "smallChange": the declared SmallChange)  // what gates; anything not listed is reported only
    "scope":    "main" | "dialog" | "all",           // main window tree, the extra windows (TaskDialog / sheet / NSAlert), or both (default all)
    "roles":    ["button", ...],                      // optional: compare only elements whose normalised role is listed (default: everything except IGNORED_ROLES)
    "ignoreNames": ["Close"],                         // element names dropped on both sides
    "roleMap":  {"AXSheet": "dialog"},                // case overrides of the Mac/Windows role -> normalised role table
    "boundsTolerancePt": 1.0,                         // only with "bounds" in fields: max |difference| of x, y, w, h in points, relative to the window client area
    // sr1-decisions #17: "boundsY" (main window only): y and height of every kept element within boundsYTolerancePt (default 0.05: measured 0.0 on every element of every
    // committed run, the layout rows agree to the point); "boundsX" (main window only): x of the elements whose role is in boundsXRoles (default: all) within
    // boundsXTolerancePt (default 0.05); "boundsCentreX" (main window only): the centre x (x + width / 2) of the elements whose role is in boundsCentreXRoles within
    // boundsCentreXTolerancePt (default 0.05; a push button measured 0.2) for centred elements, whose left edge and width follow the label's advance (Segoe vs SF, decision 2): the
    // centring is gated, the width never is.
    "dialogs":  {"count": 1},                         // optional: number of extra windows both sides must show
    "focus":    "element",                            // "element": the process-focused element (name, role) is compared as a field of the report
    "phases":   ["open", ""]                          // dump labels to compare (default [""] = the final dump): windows/uia-NN-<label>.json against mac/ax-NN-<label>.json
  }
"dialogs": {"count": N} may be {"open": 1, "": 0} to give a count per phase. Field "default": a Mac dialog button that is the Return (default) button must hold the keyboard
focus of the Windows dialog (a Mac dialog without a default button gates nothing: a task dialog always has one). Field "dialogTitle": the Windows dialog title equals the Mac
alert's message text.
Field "defaultButton" (sr1-decisions #17): the STATIC default button. UIA cannot report it (keyboard focus is false in the Sandbox, decision D7), but the Windows host log
(windows/host-NN.stdout.txt) records what it asked the TaskDialog for: `HOST_DIALOG_REQUEST ... buttons=A|B|C default=<index>`. The Mac AX dump marks the Return button
(`default`) and the Escape button (`cancel`). The Nth request is compared with the Nth dialog: the button the Windows request names as default must be the Mac's default
button; when the Mac has none (the first button is the cancel or the destructive one, D5) it must be the Mac's cancel button (a TaskDialog always has one, and the
destructive action must never be it); when the Mac has neither nothing gates. A missing request in the host log, or a missing default index, fails. Enter still gates the
behaviour (default-enter-v1); this gates the flag itself.
Normalised element: role, name, value, enabled, focus, toggle (on|off|mixed|null), bounds [x,y,w,h] pt relative to the window content origin. Elements are compared
as the depth-first sequence of the kept elements of each window group; a missing/extra element or a differing gated field fails the run.
"""
import json, re, sys
from pathlib import Path

IGNORED_ROLES = {"titlebar", "menubar", "menuitem", "window", "group", "pane", "unknown", "scrollbar", "thumb"}

# Windows UIA ControlType (ProgrammaticName without prefix) -> normalised
WIN_ROLE = {"Button": "button", "CheckBox": "checkbox", "Text": "text", "Edit": "textfield", "Image": "image", "Group": "group", "Pane": "pane", "Window": "window",
            "TitleBar": "titlebar", "MenuBar": "menubar", "MenuItem": "menuitem", "Menu": "menu", "List": "list", "ListItem": "listitem", "RadioButton": "radio",
            "Slider": "slider", "ScrollBar": "scrollbar", "Thumb": "thumb", "Hyperlink": "link", "Document": "document", "Tab": "tab", "TabItem": "tabitem", "ComboBox": "combobox",
            "ToolBar": "toolbar", "Separator": "separator", "Custom": "unknown", "ProgressBar": "progress", "Table": "table", "Tree": "tree", "TreeItem": "treeitem", "DataItem": "listitem"}
# Mac AX role (or role/subrole) -> normalised. AXSwitch is a checkbox subrole on macOS; Windows publishes a switch as a UIA Button with a toggle state (below).
MAC_ROLE = {"AXButton": "button", "AXCheckBox": "checkbox", "AXCheckBox/AXSwitch": "switch", "AXStaticText": "text", "AXTextField": "textfield", "AXTextArea": "textfield",
            "AXImage": "image", "AXGroup": "group", "AXWindow": "window", "AXSheet": "dialog", "AXDialog": "dialog", "AXScrollArea": "pane", "AXSplitGroup": "group", "AXList": "list",
            "AXRadioButton": "radio", "AXHeading": "text", "AXSlider": "slider", "AXLink": "link", "AXMenuBar": "menubar", "AXToolbar": "toolbar", "AXPopUpButton": "combobox", "AXUnknown": "unknown",
            "AXWindow/AXDialog": "window", "AXWindow/AXSystemDialog": "window", "AXWindow/AXFloatingWindow": "window", "AXButton/AXToolbarButton": "button"}
WIN_DIALOG_CLASSES = {"#32770"}   # TaskDialog / MessageBox host window class


def clean(s):
    return None if s is None else " ".join(str(s).split())


def norm_toggle_win(t):
    return {"On": "on", "Off": "off", "Indeterminate": "mixed"}.get(t) if t else None


def norm_toggle_mac(role, value):
    if role not in ("AXCheckBox", "AXRadioButton", "AXSwitch") or value is None:
        return None
    try:
        return {0: "off", 1: "on", 2: "mixed"}.get(int(float(value)))
    except (TypeError, ValueError):
        return {"on": "on", "off": "off", "mixed": "mixed"}.get(str(value).lower())


def flatten_win(node, origin, scale, role_map, out, depth=0, list_rows=False):
    """UIA node -> normalised element list (depth-first). origin = client origin in screen px, scale = px per point."""
    if node.get("role") == "TitleBar":
        return   # window chrome (system menu, minimise/maximise/close): the Mac host window is borderless, so it has none
    if depth > 0 and node.get("role") == "Window":
        return   # an owned window (a task dialog) is also listed under its owner by UIA; it is compared as its own window
    if list_rows and node.get("role") == "ListItem":
        return   # H16: the Mac AX exposes no list-row content (rows are pixel-gated only); the row subtree is not compared
    role = WIN_ROLE.get(node.get("role"), "unknown")
    toggle = norm_toggle_win(node.get("toggle"))
    if role == "button" and toggle:
        role = "switch"
    role = role_map.get(node.get("role"), role)
    b = node.get("bounds")
    bounds = None if not b else [round((b[0] - origin[0]) / scale, 2), round((b[1] - origin[1]) / scale, 2), round(b[2] / scale, 2), round(b[3] / scale, 2)]
    value = node.get("value")
    # H14: UIA nests a toggle's label as a Text child that repeats the control's name. The Mac AX tree has no such child: a switch-style toggle exposes its
    # label as a sibling text before the unnamed switch (AXCheckBox/AXSwitch), and a checkbox carries the name itself. The label is folded into that shape:
    # a switch's label text is emitted as a sibling before it (its name is then absent on the switch), a checkbox's duplicate child is dropped.
    # The control's own role, name, toggle, enabled and bounds are still compared on both sides.
    kids = node.get("children", [])
    labels = [c for c in kids if toggle and _is_toggle_label(node, c)]
    kids = [c for c in kids if not (toggle and _is_toggle_label(node, c))]
    switch_label = bool(labels) and role == "switch"
    if switch_label:
        for c in labels:
            flatten_win(c, origin, scale, role_map, out, depth, list_rows)
    level = node.get("headingLevel")
    loc = (node.get("localizedRole") or node.get("uia3LocalizedControlType") or "").lower()
    out.append(dict(role=role, name=None if switch_label else clean(node.get("name")), value=None if toggle else clean(value), enabled=bool(node.get("enabled", True)), focus=bool(node.get("focus")),
                    toggle=toggle, bounds=bounds, depth=depth, raw=node.get("role"), range=node.get("range"),
                    # ABI 0.13 extras (gated only when listed in fields): UIA FullDescription, heading (localized type or Level > 0), Hyperlink control type
                    help=clean(node.get("fullDescription")) or None, heading=loc == "heading" or (isinstance(level, (int, float)) and level > 0), link=role == "link"))
    for c in kids:
        flatten_win(c, origin, scale, role_map, out, depth + 1, list_rows)


def _is_toggle_label(node, child):
    """H14: a leaf UIA Text whose name is the toggle's own name (the label UIA nests under the control)."""
    name = clean(node.get("name"))
    return bool(name) and child.get("role") == "Text" and not child.get("children") and clean(child.get("name")) == name


def _num(v):
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def flatten_mac(node, role_map, out, depth=0, list_rows=False):
    r = node.get("role"); sub = node.get("subrole")
    if list_rows and r == "AXScrollBar":
        return   # H16: a scroll bar and its increment/decrement arrows are scroll parts, not content
    key = f"{r}/{sub}" if sub else r
    role = role_map.get(key) or role_map.get(r) or MAC_ROLE.get(key) or MAC_ROLE.get(r) or "unknown"
    if list_rows and r == "AXOutline":
        role = "list"   # H16: a SwiftUI List's AXOutline is the list itself (its rows carry no content)
    toggle = norm_toggle_mac(r, node.get("value"))
    value = node.get("value")
    # a text element's content is its value or label; Windows publishes it as Name, so fold it there
    name = node.get("name")
    if role == "text" and not name and value is not None:
        name, value = value, None
    # a text field's title is its placeholder on the Mac (AXPlaceholderValue); UIA publishes it as the Name
    if role == "textfield" and not name and node.get("placeholder"):
        name = node.get("placeholder")
    out.append(dict(role=role, name=clean(name), value=None if toggle else clean(value) if value is not None else None,
                    enabled=bool(node.get("enabled", True)), focus=bool(node.get("focus")), toggle=toggle, bounds=node.get("bounds"), depth=depth, raw=key,
                    help=clean(node.get("help")) or None, heading=r == "AXHeading" or (node.get("roleDescription") or "").lower() == "heading", link=role == "link",
                    default=bool(node.get("default")), cancel=bool(node.get("cancel")), destructive=bool(node.get("destructive")),
                    range=(dict(value=_num(node.get("value")), minimum=_num(node.get("min")), maximum=_num(node.get("max"))) if r == "AXSlider" else None)))
    for c in node.get("children", []):
        flatten_mac(c, role_map, out, depth + 1, list_rows)


def win_groups(doc, role_map, list_rows=False):
    """-> {"main": [elements], "dialogs": [[elements], ...], "focused": {...}}"""
    main, dialogs = [], []
    for w in doc.get("windows", []):
        cx, cy, cw, ch = w.get("client", w["rect"][:2] + [0, 0])
        scale = w.get("renderScale") or (w.get("dpi") or 96) / 96.0   # H17: the scale the host passed to the renderer (HOST_SCALE_GUARD) wins over the window's DPI
        els = []
        if "tree" in w:
            flatten_win(w["tree"], (cx, cy), scale, role_map, els, 0, list_rows)
        if w.get("main"):
            main = els
        else:
            dialogs.append(dict(title=clean(w.get("title")), cls=w.get("class"), elements=els))
    return dict(main=main, dialogs=dialogs, focused=doc.get("focusedElement"))


def mac_groups(doc, role_map, list_rows=False):
    main, dialogs = [], []
    for w in doc.get("windows", []):
        els = []
        if "tree" in w:
            flatten_mac(w["tree"], role_map, els, 0, list_rows)
        if w.get("main"):
            main = els
        else:
            dialogs.append(dict(title=clean(w.get("title")), cls=w.get("kind"), elements=els))
    return dict(main=main, dialogs=dialogs, focused=doc.get("focusedElement"))


def keep(elements, cfg):
    ignore = set(cfg.get("ignoreNames", []))
    roles = cfg.get("roles")
    out = []
    for e in elements:
        if e["name"] in ignore:
            continue
        if e["role"] == "text" and not e["name"] and not e["value"]:
            continue   # an empty text (a task dialog always has a content text, empty without a message)
        if roles is not None:
            if e["role"] not in roles:
                continue
        elif e["role"] in IGNORED_ROLES:
            continue
        out.append(e)
    return out


def compare_lists(label, a, b, cfg):
    """a = Windows elements, b = Mac elements -> list of mismatch dicts"""
    fields = cfg.get("fields", ["role", "name", "toggle", "enabled"])
    tol = float(cfg.get("boundsTolerancePt", 1.0))
    mm = []
    slider_ordinal = 0
    if "count" in fields and len(a) != len(b):
        mm.append(dict(where=label, field="count", windows=len(a), mac=len(b)))
    for i in range(max(len(a), len(b))):
        if i >= len(a) or i >= len(b):
            if "order" in fields or "count" in fields or "role" in fields:
                mm.append(dict(where=f"{label}[{i}]", field="missing", windows=a[i] if i < len(a) else None, mac=b[i] if i < len(b) else None))
            continue
        x, y = a[i], b[i]
        for f in fields:
            if f in ("count", "order"):
                continue
            if f in ("boundsY", "boundsX", "boundsCentreX"):
                if not label.startswith("main") or (f == "boundsX" and x["role"] not in cfg.get("boundsXRoles", [x["role"]])) or (f == "boundsCentreX" and x["role"] not in cfg.get("boundsCentreXRoles", [])):
                    continue   # the Mac alert and the TaskDialog have nothing comparable in position; only the main window's layout is
                bx, by = x["bounds"], y["bounds"]
                if bx is None or by is None:
                    if bx != by:
                        mm.append(dict(where=f"{label}[{i}]", field=f, windows=bx, mac=by))
                    continue
                t = float(cfg.get({"boundsY": "boundsYTolerancePt", "boundsX": "boundsXTolerancePt", "boundsCentreX": "boundsCentreXTolerancePt"}[f], 0.05))
                if f == "boundsCentreX":
                    wv, mv = [bx[0] + bx[2] / 2], [by[0] + by[2] / 2]
                else:
                    pairs = ((1, 3) if f == "boundsY" else (0,))
                    wv, mv = [bx[k] for k in pairs], [by[k] for k in pairs]
                if max(abs(p - q) for p, q in zip(wv, mv)) > t:
                    mm.append(dict(where=f"{label}[{i}]", field=f, windows=wv, mac=mv, tolerancePt=t, role=x["role"], name=x["name"]))
            elif f == "bounds":
                bx, by = x["bounds"], y["bounds"]
                if bx is None or by is None:
                    if bx != by:
                        mm.append(dict(where=f"{label}[{i}]", field="bounds", windows=bx, mac=by))
                elif max(abs(p - q) for p, q in zip(bx, by)) > tol:
                    mm.append(dict(where=f"{label}[{i}]", field="bounds", windows=bx, mac=by, tolerancePt=tol))
            elif f == "range":
                # a slider's range (round 6 block 37): the UIA RangeValue (value, Minimum, Maximum) against the Mac's AXValue / AXMinValue / AXMaxValue, and SmallChange against the
                # case's declared `smallChange` (a number, or a list with one per slider in tree order; the Mac's accessibility increment measured in decision H5: the step, else a tenth of the range)
                if x["role"] != "slider" and y["role"] != "slider":
                    continue
                wr, mr = x.get("range"), y.get("range")
                if wr is None or mr is None:
                    mm.append(dict(where=f"{label}[{i}]", field="range", windows=wr, mac=mr)); continue
                for k in ("value", "minimum", "maximum"):
                    if wr.get(k) is None or mr.get(k) is None or abs(float(wr[k]) - float(mr[k])) > 1e-6:
                        mm.append(dict(where=f"{label}[{i}]", field=f"range.{k}", windows=wr.get(k), mac=mr.get(k)))
                small = cfg.get("smallChange")
                if isinstance(small, list):      # one declared SmallChange per slider, in tree order
                    small = small[slider_ordinal] if slider_ordinal < len(small) else None
                slider_ordinal += 1
                if small is not None and (wr.get("smallChange") is None or abs(float(wr["smallChange"]) - float(small)) > 1e-6):
                    mm.append(dict(where=f"{label}[{i}]", field="range.smallChange", windows=wr.get("smallChange"), declared=small))
            elif f == "default":
                if y.get("default") and not x.get("focus"):
                    mm.append(dict(where=f"{label}[{i}]", field="default", windows="not focused", mac="default (Return) button", name=y["name"]))
            elif f == "name" and "nameRoles" in cfg and x["role"] not in cfg["nameRoles"]:
                continue   # names gate only for the listed roles (a hidden-label control has no name on the Mac)
            elif f == "help" and x["role"] == y["role"] == "text" and y.get("value") and y.get("value") != y.get("name"):
                # A static text's accessibilityValue (Mac AXValue) has no UIA slot of its own: AccessKit's Label takes its value as its Name, so the renderer
                # (ax.rs, rev 0.13) appends it to the FullDescription after any hint. Expected Windows help = "<Mac help>, <Mac value>" (CI 39618595219: "forty-two").
                want = ", ".join(v for v in (y.get("help"), y.get("value")) if v)
                if (x.get("help") or None) != want:
                    mm.append(dict(where=f"{label}[{i}]", field=f, windows=x.get(f), mac=want, role=(x["role"], y["role"]), note="static-text value appended to FullDescription"))
            elif (x.get(f) or None) != (y.get(f) or None) if f == "name" else x.get(f) != y.get(f):   # an element with no name is "" on Windows and absent on the Mac
                mm.append(dict(where=f"{label}[{i}]", field=f, windows=x.get(f), mac=y.get(f), role=(x["role"], y["role"])))
    return mm


def host_dialog_requests(path):
    """The HOST_DIALOG_REQUEST lines of one Windows host log, in order: [{kind, title, buttons[], default(int|None)}]. The log is OEM/ANSI text, read losslessly (latin-1)."""
    if not path.is_file():
        return None
    out = []
    for m in re.finditer(r"HOST_DIALOG_REQUEST id=\S+ node=\S+ kind=(\S+) title=(.*?) buttons=(.*?) default=(-?\d+|none)\s*$", path.read_bytes().decode("latin-1"), re.M):
        out.append(dict(kind=m.group(1), title=m.group(2), buttons=m.group(3).split("|"), default=None if m.group(4) == "none" else int(m.group(4))))
    return out


def default_button_mismatch(label, req, mac_buttons):
    """-> mismatch dict or None. req = the Windows request (or None), mac_buttons = the kept Mac button elements of the dialog."""
    mac_default = [b["name"] for b in mac_buttons if b.get("default")]
    mac_cancel = [b["name"] for b in mac_buttons if b.get("cancel")]
    expected = mac_default[0] if mac_default else (mac_cancel[0] if mac_cancel else None)
    if req is None:
        return dict(where=label, field="defaultButton", windows="no HOST_DIALOG_REQUEST in the host log", mac=expected)
    d = req["default"]
    win = req["buttons"][d] if d is not None and 0 <= d < len(req["buttons"]) else None
    if win is None:
        return dict(where=label, field="defaultButton", windows=f"default index {d} of {req['buttons']}", mac=expected)
    if expected is not None and win != expected:
        return dict(where=label, field="defaultButton", windows=win, mac=expected, rule="Mac default button" if mac_default else "Mac has no default: the cancel button")
    return None


def compare_run(win_doc, mac_doc, cfg, phase="", host_dialogs=None):
    rm = cfg.get("roleMap", {})
    list_rows = cfg.get("listRows") == "pixels-only"   # H16: list rows are not compared (the Mac exposes no row content); the pixel gate covers them
    w, m = win_groups(win_doc, rm, list_rows), mac_groups(mac_doc, rm, list_rows)
    scope = cfg.get("scope", "all")
    mm, info = [], {}
    if scope in ("main", "all"):
        a, b = keep(w["main"], cfg), keep(m["main"], cfg)
        info["main"] = dict(windows=len(a), mac=len(b))
        mm += compare_lists("main", a, b, cfg)
    if scope in ("dialog", "all"):
        want = cfg.get("dialogs", {}).get("count")
        if isinstance(want, dict):
            want = want.get(phase)
        if want is not None:
            for side, g in (("windows", w), ("mac", m)):
                if len(g["dialogs"]) != want:
                    mm.append(dict(where="dialogs", field="count", side=side, expected=want, actual=len(g["dialogs"])))
        info["dialogs"] = dict(windows=len(w["dialogs"]), mac=len(m["dialogs"]))
        for i, (da, db) in enumerate(zip(w["dialogs"], m["dialogs"])):
            a, b = keep(da["elements"], cfg), keep(db["elements"], cfg)
            if "dialogTitle" in cfg.get("fields", []) and da["title"] != db["title"]:
                mm.append(dict(where=f"dialog{i}", field="dialogTitle", windows=da["title"], mac=db["title"]))
            mm += compare_lists(f"dialog{i}", a, b, cfg)
            if "defaultButton" in cfg.get("fields", []):
                req = host_dialogs[i] if host_dialogs is not None and i < len(host_dialogs) else None
                dm = default_button_mismatch(f"dialog{i}", req, [e for e in b if e["role"] == "button"])
                if dm:
                    mm.append(dm)
    if cfg.get("focus") == "element":
        fa, fb = w["focused"], m["focused"]
        key = lambda f: None if not f else (clean(f.get("name")), WIN_ROLE.get(f.get("role"), MAC_ROLE.get(f.get("role"), f.get("role"))))
        info["focusedElement"] = dict(windows=key(fa), mac=key(fb))
        if key(fa) != key(fb):
            mm.append(dict(where="process", field="focusedElement", windows=key(fa), mac=key(fb)))
    return mm, info


def host_render_scale(stdout_path):
    """The render scale the capture host passed and the renderer reported (decision H17), from its HOST_SCALE_GUARD line; None when the
    host did not print one (a capture from before 0.10: the window's DPI is then the scale)."""
    import re
    try:
        text = Path(stdout_path).read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return None
    m = re.search(r"HOST_SCALE_GUARD requested=(\S+) renderer=(\S+) clientDPI=\S+ status=PASS", text)
    return float(m.group(2)) if m else None


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text()).get("semanticGate")
    if cfg is None:
        sys.exit("pair.json has no semanticGate")
    rows = []
    n = len(list((out / "windows").glob("uia-[0-9][0-9].json")))
    phases = cfg.get("phases", [""])
    for i in range(1, n + 1):
        mm, info, err = [], {}, None
        for phase in phases:
            suffix = f"-{phase}" if phase else ""
            wp, mp = out / f"windows/uia-{i:02d}{suffix}.json", out / f"mac/ax-{i:02d}{suffix}.json"
            if not (wp.is_file() and mp.is_file()):
                err = f"missing dump (phase '{phase}') windows={wp.is_file()} mac={mp.is_file()}"; break
            win_doc = json.loads(wp.read_text(encoding="utf-8-sig"))
            hs = host_render_scale(out / f"windows/host-{i:02d}.stdout.txt")
            if hs:
                for w_ in win_doc.get("windows", []):
                    w_["renderScale"] = hs
            pm, pinfo = compare_run(win_doc, json.loads(mp.read_text(encoding="utf-8-sig")), cfg, phase, host_dialog_requests(out / f"windows/host-{i:02d}.stdout.txt"))
            mm += [dict(m, phase=phase) for m in pm]; info[phase or "final"] = pinfo
        if err:
            rows.append(dict(run=i, verdict="fail", error=err)); continue
        rows.append(dict(run=i, verdict="pass" if not mm else "fail", compared=info, mismatches=mm))
    passed = sum(1 for r in rows if r["verdict"] == "pass")
    rep = dict(pairs=n, pass_=passed, fail=n - passed, gate=cfg, rows=rows)
    (out / "semantic-report.json").write_text(json.dumps(rep, indent=1))
    for r in rows:
        print(f"  semantic run {r['run']:02d} {r['verdict']}" + ("" if r["verdict"] == "pass" else " " + json.dumps(r.get("mismatches") or r.get("error"))[:300]))
    print(f"semantic pairs={n} pass={passed} fail={n - passed} fields={','.join(cfg.get('fields', []))} scope={cfg.get('scope', 'all')}")
    sys.exit(0 if n and passed == n else 1)


if __name__ == "__main__":
    main()
