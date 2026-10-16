#!/usr/bin/env python3
"""Unit tests for pair_semantic_report.py (python3 -m unittest factory/tools/test_pair_semantic_report.py)."""
import json, sys, tempfile, unittest, subprocess
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pair_semantic_report as S

def win_window(children, main=True, title="Alchemist FactoryProbe", cls="Zed::Window", client=(100, 200, 800, 600), dpi=240):
    root = dict(name=title, role="Window", localizedRole="region", bounds=[client[0] - 16, client[1] - 56, 832, 688], enabled=True, focus=False, children=[
        dict(name=title, role="TitleBar", bounds=[client[0], client[1] - 56, 800, 56], enabled=True, focus=False, children=[dict(name="Close", role="Button", enabled=True, focus=False, children=[])])] + children)
    return dict(hwnd=1, main=main, **{"class": cls}, title=title, rect=[0, 0, 1, 1], client=list(client), dpi=dpi, tree=root)

def win_el(name, role, x, y, w, h, client=(100, 200), **kw):
    d = dict(name=name, role=role, bounds=[client[0] + x * 2.5, client[1] + y * 2.5, w * 2.5, h * 2.5], enabled=True, focus=False, children=[])
    d.update(kw); return d

def mac_window(children, main=True, title="", kind="window"):
    return dict(main=main, title=title, kind=kind, tree=dict(role="AXWindow", name=title, enabled=True, focus=False, bounds=[0, 0, 320, 240], children=children))

def mac_el(name, role, x, y, w, h, **kw):
    d = dict(name=name, role=role, bounds=[x, y, w, h], enabled=True, focus=False, children=[]); d.update(kw); return d

class SemanticTests(unittest.TestCase):
    def test_checkbox_pass_and_toggle_mismatch(self):
        w = dict(windows=[win_window([win_el("Enabled", "CheckBox", 0, 0, 16, 16, toggle="On", value="1")])])
        m = dict(windows=[mac_window([mac_el("Enabled", "AXCheckBox", 0, 0, 16, 16, value=1)])])
        cfg = dict(fields=["role", "name", "toggle", "enabled", "bounds"], boundsTolerancePt=1)
        mm, info = S.compare_run(w, m, cfg)
        self.assertEqual(mm, []); self.assertEqual(info["main"], dict(windows=1, mac=1))
        m["windows"][0]["tree"]["children"][0]["value"] = 0
        mm, _ = S.compare_run(w, m, cfg)
        self.assertEqual([x["field"] for x in mm], ["toggle"])

    def test_switch_is_button_with_toggle_on_windows(self):
        w = dict(windows=[win_window([win_el("Enabled", "Button", 0, 0, 54, 24, toggle="Off")])])
        m = dict(windows=[mac_window([mac_el("Enabled", "AXCheckBox", 0, 0, 54, 24, subrole="AXSwitch", value=0)])])
        mm, _ = S.compare_run(w, m, dict(fields=["role", "name", "toggle"]))
        self.assertEqual(mm, [])

    def test_h14_switch_label_child_folds_into_the_mac_shape(self):
        # decision H14: UIA nests a switch's label Text under the Button; the Mac AX tree has a sibling static text before an unnamed AXSwitch
        lab = win_el("Switch", "Text", 0, 0, 40, 16)
        w = dict(windows=[win_window([win_el("Switch", "Button", 0, 0, 56, 26, toggle="On", children=[lab])])])
        m = dict(windows=[mac_window([mac_el("Switch", "AXStaticText", 0, 0, 40, 16), mac_el(None, "AXCheckBox", 0, 0, 56, 26, subrole="AXSwitch", value=1)])])
        cfg = dict(fields=["role", "name", "toggle", "enabled", "count"])
        mm, _ = S.compare_run(w, m, cfg)
        self.assertEqual(mm, [])

    def test_h14_checkbox_duplicate_label_child_is_dropped(self):
        dup = win_el("Check", "Text", 0, 0, 40, 16)
        w = dict(windows=[win_window([win_el("Check", "CheckBox", 0, 0, 80, 16, toggle="Off", children=[dup])])])
        m = dict(windows=[mac_window([mac_el("Check", "AXCheckBox", 0, 0, 80, 16, value=0)])])
        mm, _ = S.compare_run(w, m, dict(fields=["role", "name", "toggle", "enabled", "count"]))
        self.assertEqual(mm, [])

    def test_h14_mutations_still_fail_the_gate(self):
        # the fold must not hide a renamed or a missing toggle: a rename changes the switch's label, a removed switch changes the count
        lab = win_el("Switchy", "Text", 0, 0, 40, 16)
        renamed = dict(windows=[win_window([win_el("Switchy", "Button", 0, 0, 56, 26, toggle="On", children=[lab])])])
        m = dict(windows=[mac_window([mac_el("Switch", "AXStaticText", 0, 0, 40, 16), mac_el(None, "AXCheckBox", 0, 0, 56, 26, subrole="AXSwitch", value=1)])])
        cfg = dict(fields=["role", "name", "toggle", "enabled", "count"])
        mm, _ = S.compare_run(renamed, m, cfg)
        self.assertTrue(mm, "a renamed switch label must fail")
        missing = dict(windows=[win_window([])])
        mm, _ = S.compare_run(missing, m, cfg)
        self.assertTrue(any(x.get("field") == "count" for x in mm), "a missing switch must fail the count")

    def _h16_docs(self, rename_star=None, drop_list=False):
        # H16 (controls-b shape): a list of three named rows (the rows carry their text), a Star text outside the list; the Mac has an AXOutline with four
        # contentless AXUnknown rows inside an AXScrollArea whose AXScrollBar holds zero-size disabled arrows
        rows = [win_el(n, "ListItem", 0, 24 * i, 180, 24, children=[win_el(n, "Text", 2, 24 * i + 2, 40, 16)]) for i, n in enumerate(["One", "Two", "Three"])]
        kids = [win_el(rename_star or "Star", "Text", 0, 0, 30, 16)]
        if not drop_list:
            kids.append(win_el("", "List", 0, 30, 180, 90, children=rows))
        w = dict(windows=[win_window(kids)])
        outline = mac_el("", "AXOutline", 0, 30, 182, 92, children=[mac_el(None, "AXUnknown", 0, 30 + 24 * i, 0, 0) for i in range(4)])
        arrows = [mac_el(None, "AXButton", 0, 0, 0, 0, subrole="AXIncrementArrow", enabled=False), mac_el(None, "AXButton", 0, 0, 0, 0, subrole="AXDecrementArrow", enabled=False)]
        scroll = mac_el("", "AXScrollArea", 0, 30, 180, 90, enabled=False, children=[outline, mac_el("", "AXScrollBar", 0, 30, 19, 92, children=arrows)])
        m = dict(windows=[mac_window([mac_el("Star", "AXStaticText", 0, 0, 30, 16), scroll])])
        return w, m

    def test_h16_list_rows_are_not_compared_and_the_list_scroll_bar_is_not_content(self):
        w, m = self._h16_docs()
        cfg = dict(fields=["role", "name", "enabled", "count"], listRows="pixels-only")
        mm, _ = S.compare_run(w, m, cfg)
        self.assertEqual(mm, [])

    def test_h16_mutation_a_missing_list_still_fails(self):
        w, m = self._h16_docs(drop_list=True)
        cfg = dict(fields=["role", "name", "enabled", "count"], listRows="pixels-only")
        mm, _ = S.compare_run(w, m, cfg)
        self.assertTrue(any(x.get("field") in ("count", "missing") for x in mm), mm)

    def test_h16_mutation_a_missing_scroll_view_on_the_mac_still_fails(self):
        w, m = self._h16_docs()
        m["windows"][0]["tree"]["children"] = [c for c in m["windows"][0]["tree"]["children"] if c.get("role") != "AXScrollArea"]
        cfg = dict(fields=["role", "name", "enabled", "count"], listRows="pixels-only")
        mm, _ = S.compare_run(w, m, cfg)
        self.assertTrue(any(x.get("field") in ("count", "missing", "role") for x in mm), mm)

    def test_h16_mutation_a_renamed_control_outside_the_rows_still_fails(self):
        w, m = self._h16_docs(rename_star="Stars")
        cfg = dict(fields=["role", "name", "enabled", "count"], listRows="pixels-only")
        mm, _ = S.compare_run(w, m, cfg)
        self.assertTrue(any(x.get("field") == "name" for x in mm), mm)

    def test_titlebar_chrome_is_ignored_and_extra_element_fails(self):
        w = dict(windows=[win_window([win_el("A", "Text", 0, 0, 10, 10), win_el("B", "Text", 0, 20, 10, 10)])])
        m = dict(windows=[mac_window([mac_el(None, "AXStaticText", 0, 0, 10, 10, value="A")])])
        mm, _ = S.compare_run(w, m, dict(fields=["role", "name"]))
        self.assertEqual([x["field"] for x in mm], ["missing"])

    def test_bounds_tolerance(self):
        w = dict(windows=[win_window([win_el("Go", "Button", 10, 10, 50, 20)])])
        m = dict(windows=[mac_window([mac_el("Go", "AXButton", 10, 12.5, 50, 20)])])
        self.assertEqual(len(S.compare_run(w, m, dict(fields=["role", "bounds"], boundsTolerancePt=1))[0]), 1)
        self.assertEqual(S.compare_run(w, m, dict(fields=["role", "bounds"], boundsTolerancePt=3))[0], [])
        self.assertEqual(S.compare_run(w, m, dict(fields=["role"]))[0], [])

    def test_dialog_scope_buttons_order_and_count(self):
        task = win_window([win_el("Delete everything?", "Text", 0, 0, 100, 10), win_el("Delete", "Button", 0, 20, 60, 20), win_el("Cancel", "Button", 70, 20, 60, 20)], main=False, title="Confirm", cls="#32770")
        w = dict(windows=[win_window([]), task])
        sheet = mac_window([mac_el(None, "AXStaticText", 0, 0, 100, 10, value="Delete everything?"), mac_el("Delete", "AXButton", 0, 20, 60, 20), mac_el("Cancel", "AXButton", 70, 20, 60, 20)], main=False, title="", kind="sheet")
        m = dict(windows=[mac_window([]), sheet])
        cfg = dict(fields=["role", "name", "order", "count", "enabled"], scope="dialog", dialogs=dict(count=1))
        self.assertEqual(S.compare_run(w, m, cfg)[0], [])
        sheet["tree"]["children"].reverse()
        self.assertTrue(S.compare_run(w, m, cfg)[0])
        m["windows"].pop()
        mm, _ = S.compare_run(w, m, cfg)
        self.assertTrue(any(x["field"] == "count" and x.get("side") == "mac" for x in mm))

    def test_focused_element(self):
        w = dict(windows=[win_window([])], focusedElement=dict(name="OK", role="Button"))
        m = dict(windows=[mac_window([])], focusedElement=dict(name="OK", role="AXButton"))
        self.assertEqual(S.compare_run(w, m, dict(fields=["role"], focus="element"))[0], [])
        m["focusedElement"]["name"] = "Cancel"
        self.assertEqual(len(S.compare_run(w, m, dict(fields=["role"], focus="element"))[0]), 1)

    def test_cli_writes_report_and_exit_code(self):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t); (t / "case").mkdir(); (t / "run/windows").mkdir(parents=True); (t / "run/mac").mkdir()
            (t / "case/pair.json").write_text(json.dumps(dict(semanticGate=dict(fields=["role", "name"]))))
            (t / "run/windows/uia-01.json").write_text(json.dumps(dict(windows=[win_window([win_el("A", "Text", 0, 0, 1, 1)])])))
            (t / "run/mac/ax-01.json").write_text(json.dumps(dict(windows=[mac_window([mac_el("A", "AXStaticText", 0, 0, 1, 1)])])))
            r = subprocess.run([sys.executable, str(Path(S.__file__)), str(t / "case"), str(t / "run")], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(json.loads((t / "run/semantic-report.json").read_text())["pass_"], 1)
            (t / "run/mac/ax-01.json").write_text(json.dumps(dict(windows=[mac_window([mac_el("B", "AXStaticText", 0, 0, 1, 1)])])))
            self.assertEqual(subprocess.run([sys.executable, str(Path(S.__file__)), str(t / "case"), str(t / "run")], capture_output=True, text=True).returncode, 1)

    def test_default_button_must_hold_focus_only_when_mac_has_one(self):
        task = win_window([win_el("Delete", "Button", 0, 20, 60, 20), win_el("Cancel", "Button", 70, 20, 60, 20, focus=True)], main=False, title="T", cls="#32770")
        w = dict(windows=[win_window([]), task])
        def sheet(default_idx):
            kids = [mac_el("Delete", "AXButton", 0, 20, 60, 20), mac_el("Cancel", "AXButton", 70, 20, 60, 20)]
            if default_idx is not None: kids[default_idx]["default"] = True
            return dict(windows=[mac_window([]), mac_window(kids, main=False, title="T", kind="alert")])
        cfg = dict(fields=["role", "name", "default", "dialogTitle"], scope="dialog")
        self.assertEqual(S.compare_run(w, sheet(1), cfg)[0], [])                      # Mac default = Cancel, Windows focus = Cancel
        self.assertEqual(len(S.compare_run(w, sheet(0), cfg)[0]), 1)                  # Mac default = Delete, but Windows focuses Cancel
        self.assertEqual(S.compare_run(w, sheet(None), cfg)[0], [])                   # no Mac default: nothing to gate

    def test_phases_and_per_phase_dialog_counts(self):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t); (t / "case").mkdir(); (t / "run/windows").mkdir(parents=True); (t / "run/mac").mkdir()
            cfg = dict(fields=["role", "name"], phases=["open", ""], dialogs=dict(count={"open": 1, "": 0}))
            (t / "case/pair.json").write_text(json.dumps(dict(semanticGate=cfg)))
            task = win_window([win_el("OK", "Button", 0, 0, 1, 1)], main=False, title="T", cls="#32770")
            sheet = mac_window([mac_el("OK", "AXButton", 0, 0, 1, 1)], main=False, title="T", kind="alert")
            for label, wins, macs in (("-open", [win_window([]), task], [mac_window([]), sheet]), ("", [win_window([])], [mac_window([])])):
                (t / f"run/windows/uia-01{label}.json").write_text(json.dumps(dict(windows=wins)))
                (t / f"run/mac/ax-01{label}.json").write_text(json.dumps(dict(windows=macs)))
            r = subprocess.run([sys.executable, str(Path(S.__file__)), str(t / "case"), str(t / "run")], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            (t / "run/windows/uia-01.json").write_text(json.dumps(dict(windows=[win_window([]), task])))   # the dialog is still open after the press
            self.assertEqual(subprocess.run([sys.executable, str(Path(S.__file__)), str(t / "case"), str(t / "run")], capture_output=True, text=True).returncode, 1)

    def test_owned_dialog_listed_under_its_owner_is_not_compared_twice(self):
        task = win_window([win_el("OK", "Button", 0, 0, 10, 10)], main=False, title="T", cls="#32770")
        main = win_window([win_el("T", "Window", 0, 0, 10, 10, children=[win_el("OK", "Button", 0, 0, 10, 10)]), win_el("Waiting", "Text", 0, 20, 10, 10)])
        w = dict(windows=[task, main])
        m = dict(windows=[mac_window([mac_el(None, "AXStaticText", 0, 20, 10, 10, value="Waiting")]), mac_window([mac_el("OK", "AXButton", 0, 0, 10, 10)], main=False, title="T", kind="alert")])
        self.assertEqual(S.compare_run(w, m, dict(fields=["role", "name", "count"], dialogs=dict(count=1)))[0], [])

    def test_empty_content_text_of_a_messageless_dialog_is_not_an_element(self):
        task = win_window([win_el("", "Text", 0, 0, 10, 10), win_el("Copy", "Button", 0, 20, 10, 10)], main=False, title="Share", cls="#32770")
        w = dict(windows=[win_window([]), task])
        m = dict(windows=[mac_window([]), mac_window([mac_el("Copy", "AXButton", 0, 20, 10, 10)], main=False, title="Share", kind="alert")])
        self.assertEqual(S.compare_run(w, m, dict(fields=["role", "name", "count", "order", "dialogTitle"], scope="dialog"))[0], [])

    def test_real_windows_dump_flattens(self):
        # shape of an F2 dump from a real host run (checkbox): title-bar chrome is dropped, the control keeps role/toggle/bounds relative to the client origin
        w = dict(windows=[win_window([win_el("Enabled", "CheckBox", 0, 0, 16, 16, toggle="On", value="1", automationId="Root/#0/Modified/Modified/Toggle")])])
        g = S.win_groups(w, {})
        kept = S.keep(g["main"], {})
        self.assertEqual([(e["role"], e["name"], e["toggle"], e["bounds"]) for e in kept], [("checkbox", "Enabled", "on", [0.0, 0.0, 16.0, 16.0])])

if __name__ == "__main__":
    unittest.main()
