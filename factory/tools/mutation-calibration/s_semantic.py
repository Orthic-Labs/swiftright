"""Semantic gates: pair_semantic_report.py (UIA vs in-process AX dumps: role, name, value, toggle, enabled, dialogs, order, count; decisions F3, D5-D7, B4-B6)
and pair_list_report.py (List rows, text, order, selection, frames, label ink; decision A6-A8). Mutations edit the Windows UIA JSON (or the Windows capture)."""
import copy, json
from core import M
from mutlib import *
from PIL import ImageOps
import pair_list_report as L

MUTATIONS = []
add = lambda gate, *a, **k: MUTATIONS.append(M(gate, *a, **k))
GS, GL, GI = "semantic", "list", "ime"


def U(ctx, f): return ctx.p(f"windows/{f}")


def edit(fname, fn):
    """load windows/<fname>, apply fn(doc) -> description, save"""
    def f(ctx):
        d = jload(U(ctx, fname)); desc = fn(d); jsave(d, U(ctx, fname)); return f"{fname}: {desc}"
    return f


def set_key(role, name, key, value, main=True, nth=0):
    def fn(d):
        n, _ = find(d, role, name, main, nth); old = n.get(key); n[key] = value; return f"{role} '{name}' {key}: {old!r} -> {value!r}"
    return fn


def del_key(role, name, key):
    def fn(d):
        n, _ = find(d, role, name); old = n.pop(key, None); return f"{role} '{name}' {key} removed (was {old!r})"
    return fn


def remove(role, name, main=True):
    def fn(d):
        n, par = find(d, role, name, main); par["children"].remove(n); return f"{role} '{name}' removed from the tree"
    return fn


def duplicate(role, name, new_name=None, main=True):
    def fn(d):
        n, par = find(d, role, name, main); c = copy.deepcopy(n)
        if new_name: c["name"] = new_name
        par["children"].append(c); return f"extra {role} '{c['name']}' added"
    return fn


def swap(role1, name1, role2, name2, main=True):
    def fn(d):
        a, pa = find(d, role1, name1, main); b, pb = find(d, role2, name2, main)
        ia, ib = pa["children"].index(a), pb["children"].index(b); pa["children"][ia], pb["children"][ib] = b, a; return f"'{name1}' and '{name2}' swapped in tree order"
    return fn


def dialog_window(d): return [w for w in d["windows"] if not w.get("main")]


def dlg_title(new):
    def fn(d): w = dialog_window(d)[0]; old = w.get("title"); w["title"] = new; return f"dialog title {old!r} -> {new!r}"
    return fn


def dlg_drop(d): d["windows"] = [w for w in d["windows"] if w.get("main")]; return "the dialog window is gone (0 dialogs)"
def dlg_double(d): d["windows"].append(copy.deepcopy(dialog_window(d)[0])); return "a second identical dialog window (2 dialogs)"


def focus_flag(role, name, main=True):
    def fn(d):
        n, _ = find(d, role, name, main); n["focus"] = True; return f"UIA focus flag set on {role} '{name}'"
    return fn


def bounds_move(role, name, dx, dy, main=True):
    def fn(d):
        n, _ = find(d, role, name, main); n["bounds"] = [n["bounds"][0] + dx, n["bounds"][1] + dy] + n["bounds"][2:]; return f"{role} '{name}' bounds moved ({dx},{dy}) px"
    return fn


NOFOCUS = "docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag"

# ---- sem-click: Button click (final phase): role, name, enabled, count, order ----
def log_edit(rel, old, new):
    def f(ctx):
        p = ctx.p(rel); t = p.read_text(errors="replace"); assert old in t, (rel, old); p.write_text(t.replace(old, new)); return f"{rel}: '{old}' -> '{new}'"
    return f


B = "sem-click"
add(GS, B, "wrong-value", "catch", edit("uia-01.json", set_key("Text", "Count 1", "name", "Count 2")), "wrong value: the counter text")
add(GS, B, "missing-node", "catch", edit("uia-01.json", remove("Button", "Add")), "a missing node: the Add button")
add(GS, B, "wrong-role", "catch", edit("uia-01.json", set_key("Button", "Add", "role", "Text")), "a wrong role: the button published as text")
add(GS, B, "wrong-enabled", "catch", edit("uia-01.json", set_key("Button", "Add", "enabled", False)), "button published disabled")
add(GS, B, "extra-node", "catch", edit("uia-01.json", duplicate("Button", "Add", "Add")), "an extra button node")
add(GS, B, "wrong-name", "catch", edit("uia-01.json", set_key("Button", "Add", "name", "Plus")), "a wrong button name")
add(GS, B, "order-swapped", "catch", edit("uia-01.json", swap("Text", "Count 1", "Button", "Add")), "tree order swapped")
add(GS, B, "name-whitespace", "near", edit("uia-01.json", set_key("Text", "Count 1", "name", "Count   1")), "internal whitespace differs (the comparator collapses it)")
add(GS, B, "bounds-30pt-x", "catch", edit("uia-01.json", bounds_move("Button", "Add", 75, 0)), "button 30 pt out of place in x (its centre is gated, decision 17)")
add(GS, B, "bounds-x-2pt", "catch", edit("uia-01.json", bounds_move("Button", "Add", 5, 0)), "button published 2 pt (5 px) off in x")
add(GS, B, "bounds-y-2pt", "catch", edit("uia-01.json", bounds_move("Button", "Add", 0, 5)), "button published 2 pt (5 px) too low")
add(GS, B, "bounds-y-30pt", "catch", edit("uia-01.json", bounds_move("Button", "Add", 0, 75)), "button published 30 pt too low")
add(GS, B, "bounds-text-y-2pt", "catch", edit("uia-01.json", bounds_move("Text", "Count 1", 0, 5)), "the count text published 2 pt too low")
add(GS, B, "focus-flag", "catch", edit("uia-01.json", focus_flag("Button", "Add")), "wrong focus owner (UIA flag)", design=NOFOCUS)
# ---- sem-binding: Toggle state through two clicks (phases c1, c2, final) ----
B = "sem-binding"
for ph in ("c1", "c2", ""):
    f = f"uia-01-{ph}.json" if ph else "uia-01.json"; tag = ph or "final"
    add(GS, B, f"wrong-toggle-state-{tag}", "catch", edit(f, lambda d: (lambda n: (n[0].__setitem__("toggle", "Off" if n[0].get("toggle") == "On" else "On"), f"Derived toggle -> {n[0]['toggle']}")[1])(find(d, "Button", "Derived"))), "wrong toggle state")
add(GS, B, "toggle-mixed-c1", "catch", edit("uia-01-c1.json", set_key("Button", "Derived", "toggle", "Indeterminate")), "toggle published as mixed")
add(GS, B, "toggle-lost-c1", "catch", edit("uia-01-c1.json", del_key("Button", "Derived", "toggle")), "toggle state not published (a plain button)")
add(GS, B, "wrong-counter-c2", "catch", edit("uia-01-c2.json", lambda d: (lambda n: (n[0].__setitem__("name", n[0]["name"] + "0"), "count text wrong")[1])(find(d, "Text", None, True, 0))), "wrong value: the derived count text")
# ---- sem-alert-three: confirmation-style alert, open phase (dialog buttons, title, count) ----
B = "sem-alert-three"
add(GS, B, "button-renamed", "catch", edit("uia-01-open.json", set_key("Button", "Third", "name", "Fourth", False)), "wrong button set: a button renamed")
add(GS, B, "button-missing", "catch", edit("uia-01-open.json", remove("Button", "Cancel", False)), "wrong button set: Cancel missing")
add(GS, B, "button-extra", "catch", edit("uia-01-open.json", duplicate("Button", "Cancel", "OK", False)), "wrong button set: an extra OK button")
add(GS, B, "button-order", "catch", edit("uia-01-open.json", swap("Button", "First", "Button", "Third", False)), "wrong button order (default/first button last)")
add(GS, B, "button-disabled", "catch", edit("uia-01-open.json", set_key("Button", "First", "enabled", False, False)), "a dialog button disabled")
add(GS, B, "dialog-title", "catch", edit("uia-01-open.json", dlg_title("Choose!")), "wrong dialog title")
add(GS, B, "dialog-message", "catch", edit("uia-01-open.json", set_key("Text", "Pick one.", "name", "Pick two.", False)), "wrong message text")
add(GS, B, "dialog-missing", "catch", edit("uia-01-open.json", dlg_drop), "no dialog shown")
add(GS, B, "dialog-double", "catch", edit("uia-01-open.json", dlg_double), "two dialogs shown")
add(GS, B, "default-button-wrong", "catch", log_edit("windows/host-01.stdout.txt", "default=0", "default=2"), "wrong default button: the Windows TaskDialog is asked to default to Third (Mac default is First); host log HOST_DIALOG_REQUEST default=2")
add(GS, B, "default-button-wrong-cancel", "catch", log_edit("windows/host-01.stdout.txt", "default=0", "default=1"), "wrong default button: Cancel")
add(GS, B, "default-button-none", "catch", log_edit("windows/host-01.stdout.txt", "default=0", "default=none"), "no default button requested")
add(GS, B, "default-index-out-of-range", "catch", log_edit("windows/host-01.stdout.txt", "default=0", "default=7"), "default index beyond the buttons")
add(GS, B, "default-request-missing", "catch", log_edit("windows/host-01.stdout.txt", "HOST_DIALOG_REQUEST", "HOST_DIALOG_REQUESX"), "the host log records no dialog request")
add(GS, B, "default-button-uia-focus", "catch", edit("uia-01-open.json", focus_flag("Button", "Third", False)), "wrong default button: UIA keyboard focus on Third", design=NOFOCUS)
# ---- sem-alert-default: Enter must run the Mac default button (Save) ----
B = "sem-alert-default"
add(GS, B, "enter-ran-wrong-button", "catch", edit("uia-01.json", set_key("Text", "Done", "name", "Waiting")), "wrong default button: Enter ran 'Don't save' (nothing happened) instead of 'Save'")
def dlg_linger(ctx):
    d = jload(U(ctx, "uia-01.json")); o = jload(U(ctx, "uia-01-open.json")); d["windows"].append(copy.deepcopy(dialog_window(o)[0])); jsave(d, U(ctx, "uia-01.json"))
    return "uia-01.json: the open-phase dialog is still shown after Enter (the default button did nothing)"


add(GS, B, "enter-ignored", "catch", dlg_linger, "wrong default button: Enter did not dismiss the dialog")
add(GS, B, "button-set-wrong", "catch", edit("uia-01-open.json", set_key("Button", "Don't save", "name", "Discard", False)), "wrong button set")
add(GS, B, "default-button-wrong", "catch", log_edit("windows/host-01.stdout.txt", "default=0", "default=2"), "wrong default button: the Windows TaskDialog defaults to Cancel (Mac default is Save)")
B = "sem-alert-confirm"
add(GS, B, "destructive-default", "catch", log_edit("windows/host-01.stdout.txt", "default=1", "default=0"), "the destructive Delete button is the Windows default (the Mac has none and Cancel is the Escape button)")
add(GS, B, "default-button-none", "catch", log_edit("windows/host-01.stdout.txt", "default=1", "default=none"), "no default button requested")
# ---- sem-focus-tab: focus owner follows Tab (phases t1..t5), gated through the @FocusState text ----
B = "sem-focus-tab"
add(GS, B, "wrong-focus-owner-text", "catch", edit("uia-01-t2.json", set_key("Text", "focus: second", "name", "focus: first")), "wrong focus owner: the @FocusState text names the other field")
add(GS, B, "wrong-focus-owner-t5", "catch", edit("uia-01.json", set_key("Text", "focus: second", "name", "focus: none")), "wrong focus owner after the last Tab")
add(GS, B, "wrong-value", "catch", edit("uia-01-t2.json", set_key("Edit", "Second", "value", "twp")), "wrong field value")
add(GS, B, "missing-field", "catch", edit("uia-01-t3.json", remove("Edit", "Second")), "a missing node: the second field")
add(GS, B, "wrong-role", "catch", edit("uia-01-t3.json", set_key("Edit", "First", "role", "Text")), "wrong role: a field published as text")
add(GS, B, "focus-flag-wrong-field", "catch", edit("uia-01-t2.json", focus_flag("Edit", "First")), "wrong focus owner (UIA flag on the other field)", design=NOFOCUS)
# ---- sem-ime: marked text ----
B = "sem-ime"
add(GS, B, "wrong-value", "catch", edit("uia-01.json", set_key("Edit", "Name", "value", "abnj")), "wrong value: composition text differs")
add(GS, B, "value-uncommitted", "catch", edit("uia-01.json", set_key("Edit", "Name", "value", "ab")), "wrong value: composition not shown")
add(GS, B, "missing-field", "catch", edit("uia-01.json", remove("Edit", "Name")), "a missing node")


add(GI, B, "marked-range-windows", "catch", log_edit("windows/host-01.stdout.txt", "marked=2+2", "marked=0+2"), "wrong marked-text range on Windows (host HOST_FIELD log: marked=0+2, Mac marks 2+2)")
add(GI, B, "marked-range-mac", "catch", log_edit("mac-run-01.log", "marked=2+2", "marked=3+1"), "wrong marked-text range on the Mac reference (MAC_FACT log)")
add(GI, B, "marked-lost-windows", "catch", log_edit("windows/host-01.stdout.txt", "marked=2+2", "marked=none"), "marked range lost on Windows (composition committed early)")
add(GI, B, "marked-appears-on-mac-click", "catch", log_edit("mac-run-01.log", "step=0:click fieldEditor=1 text=\"ab\" selection=2+0 marked=2+0", "step=0:click fieldEditor=1 text=\"ab\" selection=2+0 marked=0+2"), "marked text present on the Mac before any composition")
add(GI, B, "marked-length-windows", "catch", log_edit("windows/host-01.stdout.txt", "marked=2+2", "marked=2+1"), "marked range one unit short on Windows")
add(GI, B, "selection-windows", "catch", log_edit("windows/host-01.stdout.txt", "selection=4+0 marked=2+2", "selection=3+0 marked=2+2"), "selected range wrong on Windows (caret inside the marked text)")
add(GI, B, "selection-mac", "catch", log_edit("mac-run-01.log", "selection=4+0 marked=2+2", "selection=4+1 marked=2+2"), "selected range wrong on the Mac reference")
add(GI, B, "text-windows", "catch", log_edit("windows/host-01.stdout.txt", "display=\"abni\"", "display=\"abnj\""), "composed string differs on Windows")
add(GI, B, "text-mac", "catch", log_edit("mac-run-01.log", "text=\"abni\"", "text=\"abno\""), "composed string differs on the Mac reference")
add(GI, B, "step-missing-windows", "catch", log_edit("windows/host-01.stdout.txt", "HOST_FIELD tag=script", "HOST_FIELD tag=scripx"), "the Windows host logged no scripted steps")
add(GI, B, "mac-log-missing", "catch", lambda ctx: (ctx.p("mac-run-01.log").unlink(), "mac-run-01.log removed")[1], "the Mac run log is missing")
add(GI, B, "marked-none-spelling", "near", log_edit("mac-run-01.log", "marked=2+0", "marked=5+0"), "an empty marked range at another location on the Mac after the click is still 'no marked text': must pass")
# ---- sem-tf-placeholder ----
B = "sem-tf-placeholder"
add(GS, B, "field-x-2pt", "catch", edit("uia-01.json", bounds_move("Edit", "Name", 5, 0)), "text field published 2 pt (5 px) too far right")
add(GS, B, "field-y-2pt", "catch", edit("uia-01.json", bounds_move("Edit", "Name", 0, 5)), "text field published 2 pt (5 px) too low")
add(GS, B, "field-x-0.04pt", "near", edit("uia-01.json", bounds_move("Edit", "Name", 0.1, 0)), "text field published 0.04 pt off in x: inside the 0.05 pt rounding tolerance, must pass")
add(GS, B, "wrong-name", "catch", edit("uia-01.json", set_key("Edit", "Name", "name", "Nom")), "wrong placeholder/name")
add(GS, B, "wrong-value", "catch", edit("uia-01.json", set_key("Edit", "Name", "value", "x")), "wrong value")
add(GS, B, "wrong-role", "catch", edit("uia-01.json", set_key("Edit", "Name", "role", "Text")), "wrong role")
add(GS, B, "missing-node", "catch", edit("uia-01.json", remove("Edit", "Name")), "a missing node")

MUTATIONS = [m for m in MUTATIONS if m is not None]


# ---------------- list gate ----------------
def rows_of(d): return L.windows_rows(d)


def li_nodes(d):
    out = []
    for w in windows_of(d, True):
        walk(w["tree"], lambda n, p, dep: out.append((n, p)) if n.get("role") == "ListItem" else None)
    return out


def li_edit(fn):
    def f(ctx):
        d = jload(U(ctx, "uia-01.json")); desc = fn(d); jsave(d, U(ctx, "uia-01.json")); return "uia-01.json: " + desc
    return f


def li_swap(d):
    n = li_nodes(d); a, b = n[0][0], n[1][0]; a["name"], b["name"] = b["name"], a["name"]; return "rows 0 and 1 swapped (order)"


def li_sel_move(d):
    n = li_nodes(d); sel = [x for x, _ in n if x.get("selected")]; other = [x for x, _ in n if not x.get("selected")][-1]
    for x in sel: x["selected"] = False
    other["selected"] = True; return f"selection moved from {[x['name'] for x in sel]} to {other['name']!r}"


def li_sel_none(d):
    for x, _ in li_nodes(d): x["selected"] = False
    return "no row selected"


def li_sel_two(d):
    for x, _ in li_nodes(d)[:2]: x["selected"] = True
    return "rows 0 and 1 both selected"


def li_drop(d): n, p = li_nodes(d)[-1]; p["children"].remove(n); return "last row missing"
def li_extra(d): n, p = li_nodes(d)[-1]; c = copy.deepcopy(n); c["name"] += " extra"; p["children"].append(c); return "an extra row"
def li_text(d): n, p = li_nodes(d)[2]; n["name"] = n["name"] + "!"; return f"row 2 text {n['name']!r}"


def li_frame(idx, key, delta):
    def fn(d):
        n, p = li_nodes(d)[idx]; b = list(n["bounds"]); b[key] += delta; n["bounds"] = b; return f"row {idx} bounds[{key}] {delta:+g} px"
    return fn


def li_frame_derived(key, beyond):
    """the largest integer shift of row 2's bounds[key] that keeps every compared frame component within rowTolerancePx (1), or one more"""
    def f(ctx):
        d0 = jload(U(ctx, "uia-01.json")); mj = jload(ctx.p("mac/list-01.json")); tol = float(ctx.cfg["listGate"].get("rowTolerancePx", 1))
        mrows = [[round(v * 2.5, 1) for v in r["frame"]] for r in mj["rows"]]
        def worst(d):
            _, w = L.windows_rows(d); return max(abs(a - b) for a, b in zip(mrows[2], w[2]["frame"]))
        best = None
        for s in range(-6, 7):
            d = copy.deepcopy(d0); n, _ = li_nodes(d)[2]; b = list(n["bounds"]); b[key] += s; n["bounds"] = b
            if worst(d) <= tol: best = max(best, s) if best is not None else s
        # shift along +: the biggest passing, then one more
        s = (best if best is not None else 0) + (1 if beyond else 0)
        n, _ = li_nodes(d0)[2]; b = list(n["bounds"]); b[key] += s; n["bounds"] = b; jsave(d0, U(ctx, "uia-01.json"))
        return f"uia-01.json: row 2 bounds[{key}] {s:+d} px; worst frame difference vs the Mac now {worst(d0):.1f} px (rowTolerancePx {tol})"
    return f


def li_h(d): n, _ = li_nodes(d)[1]; b = list(n["bounds"]); b[3] += 2; n["bounds"] = b; return "row 1 height +2 px"


def win_edit(fn, desc):
    def f(ctx):
        p = ctx.p("windows/native-01.png"); fn(ctx, p); return desc
    return f


def row_rect(ctx, i):
    mj = jload(ctx.p("mac/list-01.json")); r = mj["rows"][i]["frame"]; y, h = int(round(r[1] * 2.5)), int(round(r[3] * 2.5)); lr = ctx.cfg["listGate"]["listRect"]
    x0 = int(lr[0]) + (20 if "plain" in ctx.case.name else 40)
    return (x0, y + h // 5, x0 + 150, y + h - h // 5), (int(lr[2]) - 30, y + h // 2), (y, h)


def ink_of(ctx, im, i):
    rect, bgxy, _ = row_rect(ctx, i); return L.label_ink(im, rect, im.getpixel(bgxy))


def li_ink(i, target):
    def f(ctx):
        base = load(ctx.p("windows/native-01.png")); mac = load(ctx.p("mac/run-01.png")); rect, bgxy, _ = row_rect(ctx, i); bg = base.getpixel(bgxy); tol = int(ctx.cfg["listGate"].get("textColourTolerance", 40))
        m = ink_of(ctx, mac, i)
        for d in range(0, 150):
            for sg in (-1, 1):
                im = recolour_where(base, lambda p: p != bg, lambda p: add_delta(p, sg * d), rect); w = ink_of(ctx, im, i)
                if w and max(abs(a - b) for a, b in zip(w, m)) == target:
                    save(im, ctx.p("windows/native-01.png")); return f"row {i} label ink {sg * d:+d} levels: {w} vs Mac {m}, max channel delta {target} (tolerance {tol})"
        raise RuntimeError("unreachable")
    return f


def li_ink_missing(i):
    def f(ctx):
        im = load(ctx.p("windows/native-01.png")); rect, bgxy, _ = row_rect(ctx, i); save(fill(im, rect, im.getpixel(bgxy)), ctx.p("windows/native-01.png")); return f"row {i} label removed"
    return f


def li_hilite(mode):
    def f(ctx):
        im = load(ctx.p("windows/native-01.png")); mj = jload(ctx.p("mac/list-01.json")); sel = [r for r in mj["rows"] if r["selected"]][0]; lr = ctx.cfg["listGate"]["listRect"]
        y, h = int(round(sel["frame"][1] * 2.5)), int(round(sel["frame"][3] * 2.5)); probe = (lr[2] - 40, y + h // 2); col = im.getpixel(probe)
        if mode == "grey":
            out = recolour_where(im, lambda p: p == col, lambda p: (220, 220, 220), (lr[0], y, lr[2], y + h)); d = f"selection highlight {col} drawn grey (220): the table is not first responder"
        elif mode == "colour+1":
            out = recolour_where(im, lambda p: p == col, lambda p: add_delta(p, 1), (lr[0], y, lr[2], y + h)); d = f"selection highlight {col} 1 level off"
        else:
            out = recolour_where(im, lambda p: p == col, lambda p: (255, 255, 255), (lr[0], y, lr[2], y + h)); d = f"selection highlight {col} not drawn"
        save(out, ctx.p("windows/native-01.png")); return d
    return f


def li_hilite_row(ctx):
    im = load(ctx.p("windows/native-01.png")); mj = jload(ctx.p("mac/list-01.json")); sel = [r for r in mj["rows"] if r["selected"]][0]; lr = ctx.cfg["listGate"]["listRect"]
    y, h = int(round(sel["frame"][1] * 2.5)), int(round(sel["frame"][3] * 2.5)); out = shift_rect(im, (lr[0] + 1, y, lr[2] - 1, y + h), 0, h, im.getpixel((lr[0] + 5, y + 2)))
    save(out, ctx.p("windows/native-01.png")); return f"selection highlight painted on the row below ({h} px lower) instead of the selected row"


def li_shift(ctx):
    im = load(ctx.p("windows/native-01.png")); lr = ctx.cfg["listGate"]["listRect"]; save(shift_rect(im, tuple(lr), 1, 0, bg_of(im)), ctx.p("windows/native-01.png")); return "list pixels moved 1 px right"


def li_flip(ctx):
    im = load(ctx.p("windows/native-01.png")); lr = ctx.cfg["listGate"]["listRect"]; rect = (lr[0], 125, lr[2], 125 + 60 + 120 + 80)
    out = im.copy(); out.paste(ImageOps.flip(im.crop(rect)), rect[:2]); save(out, ctx.p("windows/native-01.png")); return "the three rows' pixels reversed top to bottom (row order, rows carry colour swatches and no text)"


for B in ("list-arrow", "list-var"):
    if B == "list-arrow":
        add(GL, B, "row-order", "catch", li_edit(li_swap), "row order: two rows swapped")
    else:
        add(GL, B, "row-order-pixels", "catch", li_flip, "row order: the rows (colour swatches, empty text) in reverse order")
    add(GL, B, "selection-moved", "catch", li_edit(li_sel_move), "wrong selection: another row selected")
    add(GL, B, "selection-none", "catch", li_edit(li_sel_none), "wrong selection: none selected")
    add(GL, B, "selection-two", "catch", li_edit(li_sel_two), "wrong selection: two rows selected")
    add(GL, B, "row-missing", "catch", li_edit(li_drop), "a missing row")
    add(GL, B, "row-extra", "catch", li_edit(li_extra), "an extra row")
    add(GL, B, "row-text", "catch", li_edit(li_text), "wrong row text")
    add(GL, B, "row-frame-y-beyond", "catch", li_frame_derived(1, True), "row frame y 1 px beyond rowTolerancePx")
    add(GL, B, "row-frame-y-at-tolerance", "near", li_frame_derived(1, False), "row frame y at rowTolerancePx: must pass")
    add(GL, B, "row-frame-x-2px", "catch", li_edit(li_frame(2, 0, 2)), "row 2 frame x 2 px off")
    add(GL, B, "row-height+2", "catch", li_edit(li_h), "row height 2 px off")
    add(GL, B, "label-ink-just-beyond", "catch", li_ink(0, 41), "row 0 label ink colour 41 levels from the Mac (tolerance 40)")
    if B == "list-arrow":
        add(GL, B, "label-ink-at-tolerance", "near", li_ink(0, 40), "row 0 label ink colour exactly 40 levels off: must pass")
    add(GL, B, "label-missing", "catch", li_ink_missing(0), "a missing element: row 0 label gone")
    add(GL, B, "highlight-grey", "catch", li_hilite("grey"), "selection highlight in the wrong colour (grey instead of accent)")
    add(GL, B, "highlight-colour+1", "catch", li_hilite("colour+1"), "selection highlight 1 level off")
    add(GL, B, "highlight-missing", "catch", li_hilite("missing"), "selection highlight not drawn")
    add(GL, B, "highlight-wrong-row", "catch", li_hilite_row, "selection highlight on the wrong row")
    add(GL, B, "pixels-shift-1px", "catch", li_shift, "1 px shift of the list pixels")
