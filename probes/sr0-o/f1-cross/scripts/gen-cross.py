#!/usr/bin/env python3
"""Generates the per-config cross-platform recording plans under probes/sr0-o/f1-cross/cross/<config>/:
   stimulus.json   logical steps (F1Assemble input; fixtureId = config id)
   steps-win.json  UIARecorder step file (Windows native routes: UIA focus/invoke/SetValue, window-targeted WM_CHAR)
   steps-mac.json  F1MacRecord step file (Mac native routes: AX focus/press/setValue, CGEvent.postToPid, fixture stdin driver)
and cross/configs.json (config -> fixture, Windows exe flags, Mac launch flags).

The Windows exe runs its own in-process script from launch (probes/sr0-s/fresh-on-bridge SelfTest.swift buildScript): it
advances on observed state and only F1/F7 wait for the recorder's release flag. The Mac fixture is driven through its stdin
driver so that the same model-level steps happen: each Mac step mirrors what the Windows in-process script does between
the external inputs. Logical steps are therefore coarse: every external input is a step, and the autonomous work that
follows it on Windows belongs to that step on both platforms.

Run:  python3 probes/sr0-o/f1-cross/scripts/gen-cross.py
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "cross"

FIXTURE_NUMBER = {f"F{n}": n for n in range(1, 10)}
F3_VARIANTS = ["list-1s", "list-3s", "vstack-1s", "vstack-3s", "lazy-1s", "lazy-3s"]
CONFIGS = ["F1", "F2", "F3", *[f"F3-{v}" for v in F3_VARIANTS], "F4", "F5", "F6", "F6-reduced", "F7", "F8", "F9"]


def rid(n, slot):
    return f"F{n:07X}-0000-4000-8000-{slot:012d}"


def field(n, slot):
    return f"row/{rid(n, slot)}/field"


def delete_button(n, slot):
    return f"row/{rid(n, slot)}/delete"


def step(sid, logical, win=None, mac=None, win_settle=500, mac_settle=500):
    return {"id": sid, "logical": logical, "win": win or [], "mac": mac or [], "winSettle": win_settle, "macSettle": mac_settle}


def stdin(**kw):
    return {"op": "stdin", "json": kw}


def focus_step(n, slot, sid):
    return step(sid, f"focus row {slot} field",
                win=[{"op": "focus", "target": {"id": field(n, slot)}}], mac=[{"op": "focus", "id": field(n, slot)}],
                win_settle=400, mac_settle=400)


def type_step(n, slot, sid, text, expect, win_extra=None, mac_extra=None, settle_extra=0, logical=None):
    return step(sid, logical or f"type {text}",
                win=[{"op": "type", "text": text}, *(win_extra or [])],
                mac=[{"op": "type", "text": text, "expectId": field(n, slot), "expectValue": expect}, *(mac_extra or [])],
                win_settle=400 + settle_extra, mac_settle=400 + settle_extra)


def plan_for(config):
    base = config.split("-")[0]
    n = FIXTURE_NUMBER[base]
    variant = config.split("-", 1)[1] if "-" in config else ""
    win_args = ["--fixture", base]
    mac_args = ["--fixture", base]
    flags = {"release_flag": False}
    if base == "F3" and variant:
        win_args += ["--f3-variant", variant]
        mac_args += ["--f3-variant", variant]
    if config == "F6-reduced":
        win_args += ["--reduced-motion-variant"]
        mac_args += ["--reduced-motion-variant"]
    initial = step("initial", "launch-and-snapshot", win_settle=500, mac_settle=500)
    steps = [initial]

    if base == "F1":
        flags["release_flag"] = True
        steps += [
            focus_step(n, 5, "focus_row5"),
            type_step(n, 5, "type_abc", "abc", "Row 5abc"),
            step("engine_insert_above", "engine inserts row at index 0",
                 win=[{"op": "touch"}, {"op": "waitFor", "target": {"id": field(n, 99)}, "ms": 15000}],
                 mac=[stdin(step="release", key="insert-above", value=0), {"op": "waitNode", "id": field(n, 99)}]),
            type_step(n, 5, "type_d", "d", "Row 5abcd", settle_extra=100),
        ]
    elif base == "F2":
        steps += [
            focus_step(n, 3, "focus_row3"),
            step("type_dash_x_then_move", "type -x; model moves row 3 to offset 8",
                 win=[{"op": "type", "text": "-x"}], mac=[
                     {"op": "type", "text": "-x", "expectId": field(n, 3), "expectValue": "Row 3-x"},
                     stdin(step="move", **{"from": 2, "to": 8})],
                 win_settle=1500, mac_settle=1500),
        ]
    elif base == "F3":
        gap = {"": 0, "list-1s": 1000, "list-3s": 3000, "vstack-1s": 1000, "vstack-3s": 3000, "lazy-1s": 1000, "lazy-3s": 3000}[variant]
        steps += [
            focus_step(n, 4, "focus_row4"),
            step("type_x_remove_reinsert", "type x; model removes row 4, reinserts it at index 3, engine releases all",
                 win=[{"op": "type", "text": "x"}],
                 mac=[{"op": "type", "text": "x", "expectId": field(n, 4), "expectValue": "Row 4x"},
                      stdin(step="remove-row", row=4, ms=gap),
                      stdin(step="insert-row", row=4, text="Row 4", index=3),
                      stdin(step="release-all")],
                 win_settle=gap + 3500, mac_settle=gap + 1500),
        ]
    elif base == "F4":
        initial["mac"] = [
            {"op": "waitEvent", "contains": f"load-{rid(n, 1)}-g0"}, {"op": "waitEvent", "contains": f"load-{rid(n, 2)}-g0"},
            stdin(step="remove-row", row=2),
            stdin(step="release", key=f"load-{rid(n, 2)}-g0", value=42),
            stdin(step="release", key=f"load-{rid(n, 1)}-g0", value=7)]
        initial["winSettle"] = 1500
        initial["macSettle"] = 1500
        initial["logical"] = "launch; model removes row 2, engine releases loads; snapshot"
        steps += [step("settled", "idle snapshot", win_settle=500, mac_settle=500)]
    elif base == "F5":
        # Both platforms start from the same wide client size (the Mac default window is 480x560 DIP, the Windows exe opens at
        # 640x480). The Windows in-process script releases update-1/insert-1 when it first observes the narrow layout, so
        # narrow must first occur in the second step on both platforms.
        initial["win"] = [{"op": "resize", "width": 720, "height": 560}]
        initial["mac"] = [stdin(step="resize", width=720, height=560)]
        initial["winSettle"] = 1500
        initial["macSettle"] = 1500
        initial["logical"] = "launch; resize client to the common start size 720x560 DIP (wide); snapshot"
        steps += [
            step("resize_narrow_release", "resize client to 360x560 DIP; engine releases update-1 and insert-1",
                 win=[{"op": "resize", "width": 360, "height": 560}],
                 mac=[stdin(step="resize", width=360, height=560), stdin(step="release", key="update-1", value=0),
                      stdin(step="release", key="insert-1", value=0)],
                 win_settle=2500, mac_settle=2500),
            step("resize_wide_again", "resize client to 720x560 DIP",
                 win=[{"op": "resize", "width": 720, "height": 560}], mac=[stdin(step="resize", width=720, height=560)],
                 win_settle=2000, mac_settle=2000),
        ]
    elif base == "F6":
        initial["mac"] = [{"op": "waitEvent", "contains": '"policy"'}, stdin(step="burst-insert")]
        initial["winSettle"] = 3000
        initial["macSettle"] = 2500
        initial["logical"] = "launch; model bursts two animated inserts; snapshot after the animation window"
        steps += [step("settled", "idle snapshot", win_settle=500, mac_settle=500)]
    elif base == "F7":
        flags["release_flag"] = True
        steps += [
            focus_step(n, 2, "focus_row2"),
            type_step(n, 2, "type_ka", "ka", "Row 2ka"),
            step("release_and_compose", "engine releases insert-above; the IME composition n, na commits as 'na'",
                 win=[{"op": "touch"}, {"op": "waitFor", "target": {"id": field(n, 99)}, "ms": 15000},
                      {"op": "waitFor", "target": {"id": field(n, 2)}, "value": "Row 2kana", "ms": 15000}],
                 mac=[stdin(step="release", key="insert-above", value=0), {"op": "waitNode", "id": field(n, 99)},
                      {"op": "typeChunk", "text": "na", "expectId": field(n, 2), "expectValue": "Row 2kana"}],
                 win_settle=1000, mac_settle=1000),
        ]
    elif base == "F8":
        steps += [
            step("invoke_insert_above", "activate the Insert above button; the engine commits it, then two restarts and a stale release",
                 win=[{"op": "invoke", "target": {"type": "Button", "name": "Insert above"}},
                      {"op": "waitFor", "target": {"id": field(n, 101)}, "ms": 30000}],
                 mac=[{"op": "press", "id": "toolbar/insert"},
                      {"op": "waitEvent", "contains": "insert-toolbar-1"},
                      stdin(step="release", key="insert-toolbar-1", value=0),
                      {"op": "waitNode", "id": field(n, 101)},
                      stdin(step="toolbar-insert"), {"op": "waitEvent", "contains": "insert-toolbar-2"},
                      stdin(step="toolbar-insert"), {"op": "waitEvent", "contains": "insert-toolbar-3"},
                      stdin(step="release", key="insert-toolbar-2", value=0),
                      {"op": "waitEvent", "contains": '"rejected"'}],
                 win_settle=2500, mac_settle=1500),
            step("set_value_row3", "set row 3 value to 'AX value' through the accessibility text-replacement route (Mac: AXSelectedText over a full AXSelectedTextRange, because SwiftUI ignores AXValue writes; Windows: ValuePattern.SetValue)",
                 win=[{"op": "setValue", "target": {"id": field(n, 3)}, "value": "AX value"}],
                 mac=[{"op": "replaceText", "id": field(n, 3), "value": "AX value"}], win_settle=600, mac_settle=600),
            focus_step(n, 3, "focus_row3"),
            step("delete_row6", "activate the Delete button of row 6",
                 win=[{"op": "invoke", "target": {"type": "Button", "name": "Delete", "after": field(n, 6)}},
                      {"op": "waitFor", "target": {"id": field(n, 6)}, "absent": True, "ms": 8000}],
                 mac=[{"op": "press", "afterId": field(n, 6), "title": "Delete"}, {"op": "waitNode", "id": field(n, 6), "absent": True}],
                 win_settle=800, mac_settle=800),
        ]
    elif base == "F9":
        initial["winSettle"] = 3000
        initial["macSettle"] = 3000
        initial["logical"] = "launch; row tasks and the screen task pending; snapshot"
        steps += [step("close_window", "close the window; the runtime tears down tasks and rejects late results",
                       win=[{"op": "close"}], mac=[stdin(step="close-window")], win_settle=1500, mac_settle=1500)]
    return {"config": config, "fixture": base, "winArgs": win_args, "macLaunchArgs": mac_args, "flags": flags,
            "steps": steps, "number": n}


N1 = {"field": "steps.nativeMapping", "allowAnyValue": True,
      "reason": "N1: native input per platform is declared in CONTRACT §4/§5 (AX/CGEvent.postToPid on Mac, UIA/SendInput VK on Windows); logical intent is compared exactly"}


def adaptations(config):
    """Reasoned, narrow allowances per config (value mappings Mac -> Windows, never allowAnyValue). Every entry is a diff
    classified `contract-permitted` in CROSS-ALL.md; recorder artifacts are fixed in the recorders instead, and runtime
    defects are NOT adapted (they stay as failing diffs)."""
    n = FIXTURE_NUMBER[config.split("-")[0]]
    row = lambda slot: f"row/{rid(n, slot)}"
    out = [N1]
    if config == "F2":
        why = ("F2 Mac oracle quirk: while the moved row holds the active field editor, macOS 27 SwiftUI List reports a stale AX "
               "tree (row 3 listed twice at its new slot, row 2 missing) until focus leaves it (probed: persists after resize, heals "
               "after focusing another row). CONTRACT F2 asserts the accessibility order is UPDATED, which Windows meets: "
               "the expected value here is the stale Mac one, the allowed Windows value is the correct order.")
        out += [{"field": "model", "nodeId": row(2), "mapping": {"<absent>": "Row 2"}, "reason": why},
                {"field": "axNodes.duplicateId", "mapping": {"2 duplicates": "0 duplicates"}, "reason": why},
                {"field": "axNodes.presence", "nodeId": row(2) + "/field", "mapping": {"<absent>": "role=text-field"}, "reason": why},
                {"field": "axNodes.presence", "nodeId": row(2) + "/local", "mapping": {"<absent>": "role=static-text"}, "reason": why},
                {"field": "axNodes.parent", "nodeId": row(3) + "/field", "mapping": {"anon:anon:window#1#1": "anon:anon:window#1#7"}, "reason": why},
                {"field": "axNodes.parent", "nodeId": row(3) + "/local", "mapping": {"anon:anon:window#1#1": "anon:anon:window#1#7"}, "reason": why}]
    if config in ("F3", "F3-list-1s", "F3-list-3s"):
        why = ("F3 List: after the remove/reinsert the Mac @FocusState event reports row 4 focused (the RESULT.md oracle: List "
               "restores focus) but the Mac AX focused element is the outline, not the field (AppKit first responder is not "
               "restored on the recreated cell). Windows restores focus to the field and UIA reports it, matching the FocusState "
               "oracle. Only this one transition is allowed.")
        out += [{"field": "focusedNodeId", "mapping": {"<none>": row(4) + "/field"}, "reason": why},
                {"field": "selection", "mapping": {"<none>": "location=0 length=0"}, "reason": why}]
    if config == "F5":
        why = ("macOS (AppKit key-view loop) gives the first text field initial focus in this non-List window; Windows has no "
               "initial focus. Initial focus is not a CONTRACT F5 assertion (containment, caret clipping, AX bounds). The "
               "selection value is the Mac field's caret (at the end of 'Row 1 updated 0') while it holds that focus.")
        out += [{"field": "focusedNodeId", "mapping": {row(1) + "/field": "<none>"}, "reason": why},
                {"field": "selection", "mapping": {"location=15 length=0": "<none>"}, "reason": why}]
    if config == "F6":
        why = ("SwiftUI rebuilds the interrupted animated rows (extra disappear/appear pair per row, fixtures RESULT.md: the B pair "
               "even varies run to run on the Mac). Row view rebuild during an animated insert is not a CONTRACT F6 assertion "
               "(interruption recorded, final layout settled, completion order); the fresh runtime keeps the row views.")
        for slot in (200, 201):
            out += [{"field": "lifecycle.count", "nodeId": f"appear:{row(slot)}", "mapping": {"2": "1"}, "reason": why},
                    {"field": "lifecycle.count", "nodeId": f"disappear:{row(slot)}", "mapping": {"1": "0"}, "reason": why}]
    if config == "F8":
        why = ("Activation by the accessibility route: AccessKit/UIA Invoke moves keyboard focus to the invoked control (the "
               "runtime logs ax-button-focus), AXPress on macOS does not. CONTRACT F8 does not specify focus after an activation.")
        out += [{"field": "focusedNodeId", "mapping": {"<none>": "toolbar/insert"}, "reason": why}]
    if config == "F9":
        why = ("CONTRACT F9: tree release after close is a Windows runtime requirement, not a Mac oracle assertion "
               "(AppKit keeps closed NSWindows alive in the fixture host).")
        out += [{"field": "lifecycle.count", "nodeId": "treeReleased:tree", "mapping": {"0": "1"}, "reason": why}]
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    index = {}
    for config in CONFIGS:
        p = plan_for(config)
        d = OUT / config
        d.mkdir(parents=True, exist_ok=True)
        if config == "F1":   # F1 keeps its accepted stimulus and Windows steps verbatim (the accepted baseline pins sourceHash)
            (d / "stimulus.json").write_text((OUT.parent / "f1-stimulus.json").read_text())
            (d / "steps-win.json").write_text((OUT.parent / "f1-steps-win.json").read_text())
            (d / "steps-mac.json").write_text(json.dumps({"launchArgs": p["macLaunchArgs"], "steps": [
                {"id": s["id"], "logicalAction": s["logical"], "ops": s["mac"], "settleMs": s["macSettle"]} for s in p["steps"]]},
                indent=2, sort_keys=True) + "\n")
            (d / "adapt-v0.json").write_text(json.dumps(adaptations(config), indent=2, sort_keys=True, ensure_ascii=False) + "\n")
            index[config] = {"fixture": p["fixture"], "winArgs": " ".join(p["winArgs"]), "releaseFlag": p["flags"]["release_flag"]}
            continue
        stim = {"fixtureId": config, "description": f"{config} cross-platform logical script (gen-cross.py)",
                "modelRows": "all",
                "steps": [{"id": s["id"], "logicalAction": s["logical"]} for s in p["steps"]]}
        if p["fixture"] == "F9":
            stim["ignoreEffectsInSteps"] = ["close_window"]
            stim["ignoreEffectsReason"] = ("Windows' in-process script releases the pending engine calls after the close (late results rejected); "
                                           "the Mac interactive process exits when its last window closes, so it can never receive that release. "
                                           "The Windows self-test asserts the late-result rejection itself.")
        if p["fixture"] == "F6" and config == "F6":
            stim["declaredOrder"] = [{"before": "animation-start:animation/A", "after": "animation-complete:animation/A"},
                                     {"before": "animation-start:animation/B", "after": "animation-complete:animation/B"}]
        win = {"fixtureId": config, "sourceHash": "", "steps": [
            {"id": s["id"], "logicalAction": s["logical"], "ops": s["win"], "capture": True, "settleMs": s["winSettle"]} for s in p["steps"]]}
        mac = {"launchArgs": p["macLaunchArgs"], "steps": [
            {"id": s["id"], "logicalAction": s["logical"], "ops": s["mac"], "settleMs": s["macSettle"]} for s in p["steps"]]}
        for name, obj in (("stimulus.json", stim), ("steps-win.json", win), ("steps-mac.json", mac)):
            (d / name).write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
        (d / "adapt-v0.json").write_text(json.dumps(adaptations(config), indent=2, sort_keys=True, ensure_ascii=False) + "\n")
        index[config] = {"fixture": p["fixture"], "winArgs": " ".join(p["winArgs"]), "releaseFlag": p["flags"]["release_flag"]}
    (OUT / "configs.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    print(f"wrote {len(CONFIGS)} configs under {OUT}")


if __name__ == "__main__":
    main()
