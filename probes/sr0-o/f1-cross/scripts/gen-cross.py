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

adapt-v0.json holds the comparator allowances. Every allowance is scoped to ONE fixture (the config id), named steps, one leaf,
and for node leaves one node, with exact value pairs (TraceKit `Adaptation`): it never applies anywhere else, and an entry that
is not fully scoped is ignored by the comparator. `status` says how well the reason is established: "contract" (CONTRACT text),
"oracle-quirk" (Mac oracle behaviour probed), "unproven" (plausible, not yet settled by a probe: see PROBES and CROSS-ALL.md).

PROBES are extra plans that are not part of the 16 SR0 configs: the same recording plan plus steps that would settle an
unproven allowance. They have no recordings yet and are never compared by the runner until recorded on both platforms.

Run:  python3 probes/sr0-o/f1-cross/scripts/gen-cross.py
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "cross"

FIXTURE_NUMBER = {f"F{n}": n for n in range(1, 10)}
F3_VARIANTS = ["list-1s", "list-3s", "vstack-1s", "vstack-3s", "lazy-1s", "lazy-3s"]
CONFIGS = ["F1", "F2", "F3", *[f"F3-{v}" for v in F3_VARIANTS], "F4", "F5", "F6", "F6-reduced", "F7", "F8", "F9"]
# probe id -> (base config, extra steps appended to the base plan)
PROBES = {"F3-list-1s-typeafter": "F3-list-1s", "F9-keepalive": "F9", "F5-nosize": "F5"}


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


def probe_steps(probe):
    """Steps appended to the base plan of a probe (purely additive: the base steps and their order are unchanged)."""
    if probe == "F3-list-1s-typeafter":
        # Settles P2 (F3 List after remove/reinsert: Mac AX focus is the outline, the FocusState event and Windows say row 4):
        # where does a typed character land? No expectation is set, the model and the focus say where it went.
        return [step("type_after_reinsert", "type y once more; where it lands shows whether row 4 really holds focus",
                     win=[{"op": "type", "text": "y"}], mac=[{"op": "type", "text": "y"}], win_settle=800, mac_settle=800)]
    raise KeyError(probe)


def plan_for(config):
    if config in PROBES:
        plan = plan_for(PROBES[config])
        plan["config"] = config
        if config == "F9-keepalive":
            # R8: the Mac process stays alive after the close and receives the same late releases the Windows script sends.
            # The release rides in the close_window step so both platforms attribute the late results to the same step.
            plan["macLaunchArgs"] = plan["macLaunchArgs"] + ["--variant", "keepalive"]     # Windows keeps its F9 args
            for s in plan["steps"]:
                if s["id"] == "close_window":
                    s["logical"] = "close the window; the runtime tears down tasks and rejects late results"
                    s["mac"] = [stdin(step="close-window"), stdin(step="release-all")]
            return plan
        if config == "F5-nosize":
            # R5: no forced start size. Each platform lays out at its own default window size; the later resize steps stay.
            initial = plan["steps"][0]
            initial["win"] = []
            initial["mac"] = []
            initial["winSettle"] = 2000
            initial["macSettle"] = 2000
            initial["logical"] = "launch at the platform's own default window size (no resize); snapshot"
            return plan
        plan["steps"] = plan["steps"] + probe_steps(config)
        return plan
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


N1_REASON = ("N1: native input per platform is declared in CONTRACT §4/§5 (AX/CGEvent.postToPid on Mac, UIA/SendInput VK on Windows); "
             "logical intent is compared exactly")


def adaptations(config, step_ids):
    """The comparator allowances of one config, in the scoped TraceKit format. Every entry is bound to this config (`fixture`),
    its `steps`, one leaf and, for node leaves, one node, with exact Mac -> Windows value pairs.

    Only differences with a standing reason remain (CROSS-ALL.md):
      N1  steps.nativeMapping, every step of the config (the declared per-platform input routes)
      P1  F2 stale Mac AX tree after the focused row moved                      status oracle-quirk
      P2  F3 List after remove/reinsert: Mac AX focus (outline) vs FocusState    status oracle-quirk (probe F3-list-1s-typeafter, tuple 09)
      P6  F9 treeReleased after close                                            status contract
      C11 F6 rows 200/201 appear/disappear counts (proposed CONTRACT C11)        status contract (proposed)
    Removed after the review: P3 (F5 initial focus), P4 (F6 row rebuild), P5 (F8 focus after Invoke) are product differences
    and stay failing diffs; recorder artifacts are fixed in the recorders, runtime defects are never adapted."""
    base = config.split("-")[0]
    n = FIXTURE_NUMBER[base]
    row = lambda slot: f"row/{rid(n, slot)}"
    out = [{"id": "N1", "status": "contract", "fixture": config, "steps": list(step_ids), "field": "steps.nativeMapping",
            "allowAnyValue": True, "reason": N1_REASON}]

    def pair(allowance_id, status, steps, field, mapping, why, node=None):
        entry = {"id": allowance_id, "status": status, "fixture": config, "steps": steps, "field": field, "mapping": mapping, "reason": why}
        if node:
            entry["nodeId"] = node
        out.append(entry)

    root = config[:-len("-typeafter")] if config.endswith("-typeafter") else config      # a probe carries its base config's allowances
    if root == "F2":
        why = ("F2 Mac oracle quirk: while the moved row holds the active field editor, macOS 27 SwiftUI List reports a stale AX "
               "tree (row 3 listed twice at its new slot, row 2 missing) until focus leaves it (probed: persists after resize, heals "
               "after focusing another row; absent when the moved row is not focused). CONTRACT F2 asserts the accessibility order "
               "is UPDATED, which Windows meets: the expected value here is the stale Mac one, the allowed Windows value is the "
               "correct order. Applies only to the step that moves the focused row.")
        step = ["type_dash_x_then_move"]
        pair("P1", "oracle-quirk", step, "model", {"<absent>": "Row 2"}, why, row(2))
        pair("P1", "oracle-quirk", step, "axNodes.duplicateId", {"2 duplicates": "0 duplicates"}, why)
        pair("P1", "oracle-quirk", step, "axNodes.presence", {"<absent>": "role=text-field"}, why, row(2) + "/field")
        pair("P1", "oracle-quirk", step, "axNodes.presence", {"<absent>": "role=static-text"}, why, row(2) + "/local")
        pair("P1", "oracle-quirk", step, "axNodes.parent", {"anon:anon:window#1#1": "anon:anon:window#1#7"}, why, row(3) + "/field")
        pair("P1", "oracle-quirk", step, "axNodes.parent", {"anon:anon:window#1#1": "anon:anon:window#1#7"}, why, row(3) + "/local")
    if root in ("F3", "F3-list-1s", "F3-list-3s"):
        why = ("F3 List after the remove/reinsert: the Mac @FocusState event reports row 4 focused (the RESULT.md oracle: List "
               "restores focus) but the Mac AX focused element is the outline, not the field, and a key typed afterwards lands "
               "nowhere on the Mac (probe F3-list-1s-typeafter, 3 Mac runs: row 4 stays 'Row 4', no focus). Windows restores "
               "focus to the field (selection 0+0) and a typed key lands in row 4 (3 Windows runs). The Mac keyboard focus is "
               "really lost, so this is a Mac oracle quirk against its own FocusState event, not a Windows defect. Applies only "
               "to the step that removes and reinserts the focused row; the later typed character is NOT allowed.")
        step = ["type_x_remove_reinsert"]
        pair("P2", "oracle-quirk", step, "focusedNodeId", {"<none>": row(4) + "/field"}, why)
        pair("P2", "oracle-quirk", step, "selection", {"<none>": "location=0 length=0"}, why)
    if root == "F6":
        why = ("Proposed CONTRACT C11: onAppear/onDisappear counts for List rows inserted under an animation are unspecified. "
               "macOS SwiftUI re-creates every List row inserted under an animation when its insertion animation completes "
               "(row 201 too, which was never interrupted): appear twice, disappear once. The fresh runtime keeps the row views "
               "(appear once, disappear zero). Exactly these four counts, rows 200 and 201, step initial; the interruption record, "
               "completion pair, final layout and every other count stay exact.")
        for slot in (200, 201):
            pair("C11", "contract", ["initial"], "lifecycle.count", {"2": "1"}, why, f"appear:{row(slot)}")
            pair("C11", "contract", ["initial"], "lifecycle.count", {"1": "0"}, why, f"disappear:{row(slot)}")
    if root == "F9":
        why = ("CONTRACT F9: tree release after close is a Windows runtime requirement, not a Mac oracle assertion "
               "(AppKit keeps closed NSWindows alive in the fixture host).")
        pair("P6", "contract", ["close_window"], "lifecycle.count", {"0": "1"}, why, "treeReleased:tree")
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    index = {}
    for config in [*CONFIGS, *PROBES]:
        p = plan_for(config)
        d = OUT / config
        d.mkdir(parents=True, exist_ok=True)
        if config == "F1":   # F1 keeps its accepted stimulus and Windows steps verbatim (the accepted baseline pins sourceHash)
            (d / "stimulus.json").write_text((OUT.parent / "f1-stimulus.json").read_text())
            (d / "steps-win.json").write_text((OUT.parent / "f1-steps-win.json").read_text())
            (d / "steps-mac.json").write_text(json.dumps({"launchArgs": p["macLaunchArgs"], "steps": [
                {"id": s["id"], "logicalAction": s["logical"], "ops": s["mac"], "settleMs": s["macSettle"]} for s in p["steps"]]},
                indent=2, sort_keys=True) + "\n")
            (d / "adapt-v0.json").write_text(json.dumps(adaptations(config, [s["id"] for s in p["steps"]]), indent=2, sort_keys=True, ensure_ascii=False) + "\n")
            index[config] = {"fixture": p["fixture"], "winArgs": " ".join(p["winArgs"]), "releaseFlag": p["flags"]["release_flag"]}
            continue
        stim = {"fixtureId": config, "description": f"{config} cross-platform logical script (gen-cross.py)",
                "modelRows": "all",
                "steps": [{"id": s["id"], "logicalAction": s["logical"]} for s in p["steps"]]}
        if config == "F5-nosize":      # R5: keep every layout pass (opt-in assembler flag) so the settle sequence is visible
            stim["keepLayoutPasses"] = True
        if config == "F9":      # F9-keepalive compares effects in every step (no ignore)
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
        (d / "adapt-v0.json").write_text(json.dumps(adaptations(config, [s["id"] for s in p["steps"]]), indent=2, sort_keys=True, ensure_ascii=False) + "\n")
        index[config] = {"fixture": p["fixture"], "winArgs": " ".join(p["winArgs"]), "releaseFlag": p["flags"]["release_flag"]}
        if config in PROBES:
            index[config]["probe"] = PROBES[config]    # not one of the 16 SR0 configs: no recordings, never compared by the runner
    (OUT / "configs.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    print(f"wrote {len(CONFIGS)} configs and {len(PROBES)} probe plans under {OUT}")


if __name__ == "__main__":
    main()
