#!/usr/bin/env python3
"""F3 semantic comparator: Windows UI Automation dump (F2: windows/uia-NN.json) against the Mac in-process accessibility dump (mac/ax-NN.json, written by the
Mac capture host with factory/tools/mac-ax-dump/AXDump.swift; no AX API across processes, no TCC prompt).

  pair_semantic_report.py <case-dir> <run-dir>      -> <run-dir>/semantic-report.json, one line per run, exit 0 when every run passes

The gate comes from <case>/pair.json "semanticGate":
  {
    "fields":   ["role","name","toggle","enabled","focus","value","bounds","order","count"],  // what gates; anything not listed is reported only
    "scope":    "main" | "dialog" | "all",           // main window tree, the extra windows (TaskDialog / sheet / NSAlert), or both (default all)
    "roles":    ["button", ...],                      // optional: compare only elements whose normalised role is listed (default: everything except IGNORED_ROLES)
    "ignoreNames": ["Close"],                         // element names dropped on both sides
    "roleMap":  {"AXSheet": "dialog"},                // case overrides of the Mac/Windows role -> normalised role table
    "boundsTolerancePt": 1.0,                         // only with "bounds" in fields: max |difference| of x, y, w, h in points, relative to the window client area
    "dialogs":  {"count": 1},                         // optional: number of extra windows both sides must show
    "focus":    "element",                            // "element": the process-focused element (name, role) is compared as a field of the report
    "phases":   ["open", ""]                          // dump labels to compare (default [""] = the final dump): windows/uia-NN-<label>.json against mac/ax-NN-<label>.json
  }
"dialogs": {"count": N} may be {"open": 1, "": 0} to give a count per phase. Field "default": a Mac dialog button that is the Return (default) button must hold the keyboard
focus of the Windows dialog (a Mac dialog without a default button gates nothing: a task dialog always has one). Field "dialogTitle": the Windows dialog title equals the Mac
alert's message text.
Normalised element: role, name, value, enabled, focus, toggle (on|off|mixed|null), bounds [x,y,w,h] pt relative to the window content origin. Elements are compared
as the depth-first sequence of the kept elements of each window group; a missing/extra element or a differing gated field fails the run.
"""
import json, sys
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
            "AXRadioButton": "radio", "AXSlider": "slider", "AXLink": "link", "AXMenuBar": "menubar", "AXToolbar": "toolbar", "AXPopUpButton": "combobox", "AXUnknown": "unknown",
            "AXWindow/AXDialog": "dialog", "AXWindow/AXSystemDialog": "dialog", "AXWindow/AXFloatingWindow": "dialog", "AXButton/AXToolbarButton": "button"}
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


def flatten_win(node, origin, scale, role_map, out, depth=0):
    """UIA node -> normalised element list (depth-first). origin = client origin in screen px, scale = px per point."""
    if node.get("role") == "TitleBar":
        return   # window chrome (system menu, minimise/maximise/close): the Mac host window is borderless, so it has none
    role = WIN_ROLE.get(node.get("role"), "unknown")
    toggle = norm_toggle_win(node.get("toggle"))
    if role == "button" and toggle:
        role = "switch"
    role = role_map.get(node.get("role"), role)
    b = node.get("bounds")
    bounds = None if not b else [round((b[0] - origin[0]) / scale, 2), round((b[1] - origin[1]) / scale, 2), round(b[2] / scale, 2), round(b[3] / scale, 2)]
    value = node.get("value")
    out.append(dict(role=role, name=clean(node.get("name")), value=None if toggle else clean(value), enabled=bool(node.get("enabled", True)), focus=bool(node.get("focus")),
                    toggle=toggle, bounds=bounds, depth=depth, raw=node.get("role")))
    for c in node.get("children", []):
        flatten_win(c, origin, scale, role_map, out, depth + 1)


def flatten_mac(node, role_map, out, depth=0):
    r = node.get("role"); sub = node.get("subrole")
    key = f"{r}/{sub}" if sub else r
    role = role_map.get(key) or role_map.get(r) or MAC_ROLE.get(key) or MAC_ROLE.get(r) or "unknown"
    toggle = norm_toggle_mac(r, node.get("value"))
    value = node.get("value")
    # a text element's content is its value or label; Windows publishes it as Name, so fold it there
    name = node.get("name")
    if role == "text" and not name and value is not None:
        name, value = value, None
    out.append(dict(role=role, name=clean(name), value=None if toggle else clean(value) if value is not None else None,
                    enabled=bool(node.get("enabled", True)), focus=bool(node.get("focus")), toggle=toggle, bounds=node.get("bounds"), depth=depth, raw=key,
                    default=bool(node.get("default")), cancel=bool(node.get("cancel")), destructive=bool(node.get("destructive"))))
    for c in node.get("children", []):
        flatten_mac(c, role_map, out, depth + 1)


def win_groups(doc, role_map):
    """-> {"main": [elements], "dialogs": [[elements], ...], "focused": {...}}"""
    main, dialogs = [], []
    for w in doc.get("windows", []):
        cx, cy, cw, ch = w.get("client", w["rect"][:2] + [0, 0])
        scale = (w.get("dpi") or 96) / 96.0
        els = []
        if "tree" in w:
            flatten_win(w["tree"], (cx, cy), scale, role_map, els)
        if w.get("main"):
            main = els
        else:
            dialogs.append(dict(title=clean(w.get("title")), cls=w.get("class"), elements=els))
    return dict(main=main, dialogs=dialogs, focused=doc.get("focusedElement"))


def mac_groups(doc, role_map):
    main, dialogs = [], []
    for w in doc.get("windows", []):
        els = []
        if "tree" in w:
            flatten_mac(w["tree"], role_map, els)
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
            if f == "bounds":
                bx, by = x["bounds"], y["bounds"]
                if bx is None or by is None:
                    if bx != by:
                        mm.append(dict(where=f"{label}[{i}]", field="bounds", windows=bx, mac=by))
                elif max(abs(p - q) for p, q in zip(bx, by)) > tol:
                    mm.append(dict(where=f"{label}[{i}]", field="bounds", windows=bx, mac=by, tolerancePt=tol))
            elif f == "default":
                if y.get("default") and not x.get("focus"):
                    mm.append(dict(where=f"{label}[{i}]", field="default", windows="not focused", mac="default (Return) button", name=y["name"]))
            elif x.get(f) != y.get(f):
                mm.append(dict(where=f"{label}[{i}]", field=f, windows=x.get(f), mac=y.get(f), role=(x["role"], y["role"])))
    return mm


def compare_run(win_doc, mac_doc, cfg, phase=""):
    rm = cfg.get("roleMap", {})
    w, m = win_groups(win_doc, rm), mac_groups(mac_doc, rm)
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
    if cfg.get("focus") == "element":
        fa, fb = w["focused"], m["focused"]
        key = lambda f: None if not f else (clean(f.get("name")), WIN_ROLE.get(f.get("role"), MAC_ROLE.get(f.get("role"), f.get("role"))))
        info["focusedElement"] = dict(windows=key(fa), mac=key(fb))
        if key(fa) != key(fb):
            mm.append(dict(where="process", field="focusedElement", windows=key(fa), mac=key(fb)))
    return mm, info


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
            pm, pinfo = compare_run(json.loads(wp.read_text(encoding="utf-8-sig")), json.loads(mp.read_text(encoding="utf-8-sig")), cfg, phase)
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
