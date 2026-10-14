"""Turn the calibration rows into results.json (summary + findings) and RESULTS.md."""
import json, time
from collections import OrderedDict, defaultdict
from pathlib import Path

GATES = OrderedDict([
    ("pixel", ("factory/tools/pair.py compare() + edge_gate()", "exact, edge-aa<=32 band (decision 5), hazeTolerance 3 (D9), named exclusions (decision 2), capture size, half-pixel tie cases (blocks-6-10/pixel-ties)")),
    ("text", ("factory/tools/pair_text_report.py", "glyph-region ink bbox within 1 px, exact outside the region (decision 2, block 4)")),
    ("text-colour", ("factory/tools/pair_textcolour_report.py", "strongest ink colour within 24/255 per channel (decisions 2, 10, 11; A1; D1)")),
    ("button", ("factory/tools/pair_button_report.py", "push Button height/y, caps, flat bands, label centre and ink (decision 11; A1-A3)")),
    ("control", ("factory/tools/pair_control_report.py", "labelled Toggle control size/y/edges, label centre (1 px), row leading x, label first ink x, label-to-control gap (decisions 7, 8, 16)")),
    ("list", ("factory/tools/pair_list_report.py", "List rows, text, order, selection, frames within 1 px, label ink (A6-A9)")),
    ("semantic", ("factory/tools/pair_semantic_report.py", "UIA vs AX: role, name, value, toggle, enabled, dialogs, order, count, static default button from the host log (F3; B4-B6, D4-D7, A4; decision 17)")),
    ("ime", ("factory/tools/pair_ime_report.py", "IME marked range, selected range and composed text per step, Windows HOST_FIELD log vs Mac MAC_FACT log (decision 15)")),
    ("clock", ("factory/tools/pair_clock_report.py", "F1 manual clock: extent, leading and trailing edge position (C2 1 px; spring 2 px; decision 18), pixels outside strips, progress (C1-C10)")),
    ("image", ("factory/tools/pair_image_report.py", "Image(systemName:) frame, ink bbox, tint (decision 3)")),
    ("text-origin", ("factory/tools/pair_textorigin_report.py", "TextField first ink x and y, baseline, selection colour and start, caret (decisions 12, 13, 14)")),
    ("multi-run", ("factory/tools/pair.py --recompare over N runs", "the case verdict is every run passing: one bad run of three must fail")),
])

NOT_CALIBRATED = [
    ("Real IME / TSF / Narrator behaviour", "needs Windows hardware; the Sandbox drives IME in-process (decisions B6, D8). Only the comparators on those dumps are calibrated."),
    ("UIA keyboard focus and OS-level focus restore", "UIA reports no keyboard focus in the Sandbox (decision D7), so the gates never read it; nothing to calibrate offline."),
    ("The capture hosts themselves (Windows renderer paint, Mac NSHostingView / AXDump / AlertHooks / MAC_FACT writers)", "they produce the evidence the comparators read; checking them needs new captures, which this pass excludes. Mutations assume the recorded Mac side is the truth."),
    ("Case-level options no shipped case exercises (the full \"bounds\" semantic field with boundsTolerancePt, a non-zero firstInkTolerancePx or selectionStartTolerancePx, the dark/pressed/focused button states, scales 1.25 and 1.5)", "there is no real run evidence to mutate; unit tests in factory/tools/test_pair_*.py cover bounds, default button and tolerance on synthetic dumps only."),
    ("Runtime unit suites (Swift: runtime 333, host 121, bridge 51) and the consolidation driver (factory/pipeline/consolidation/run_all.py)", "they are not run-evidence comparators; the driver records pair.py's exit status, which the harness does exercise."),
    ("What the default-button gate reads (decision 17)", "the Windows host's request to the TaskDialog (HOST_DIALOG_REQUEST default=N in the host log), not an observation of the dialog: UIA cannot show it (D7). That the TaskDialog honours the request is the Enter case's behaviour check (default-enter-v1), and a host log that lies about its own request is not mutated beyond the edits listed."),
    ("Non-ASCII composed text in the IME gate (decision 15)", "the Windows host log is written in the console code page, so only the ASCII prefix and the presence of a continuation are compared from the logs; the exact characters are compared on the final frame by the semantic gate from UIA values, and the intermediate non-ASCII steps are not compared character by character."),
    ("Leading-edge tolerance of the clock gate (decision 18)", "the leading edge measured 0.000 px on every committed clock run but is gated at the named 1 px (springs 2 px), so a 1 px translation of a 1 px case and a 2 px translation of a spring case pass by design."),
    ("Provenance gates (stage identity in build.json, renderer sha256, receipts)", "the lean loop (decision 4) records them but no comparator reads them; earlier provenance fault controls live in factory/pipeline/paired-five-seeded-observations-actual-v4/fault-controls.json."),
]


def summarise(rows):
    per = OrderedDict()
    for g in GATES:
        rs = [r for r in rows if r["gate"] == g]
        if not rs:
            continue
        catch = [r for r in rs if r["kind"] == "catch"]; near = [r for r in rs if r["kind"] == "near"]
        caught = [r for r in catch if r["verdict"].startswith("caught")]
        missed = [r for r in catch if r["verdict"] == "MISSED"]
        per[g] = OrderedDict(
            comparator=GATES[g][0], gates=GATES[g][1], mutations=len(catch), caught=len(caught),
            caughtByAnotherGateOnly=sum(1 for r in caught if "another gate" in r["verdict"]), caughtByComparatorCrash=sum(1 for r in caught if "crashed" in r["verdict"]),
            missed=len(missed), missedUndocumented=sum(1 for r in missed if not r["design"]), missedDocumentedExclusion=sum(1 for r in missed if r["design"]),
            nearMisses=len(near), nearMissPassed=sum(1 for r in near if r["verdict"] == "near-miss passed"), overStrict=sum(1 for r in near if r["verdict"] == "OVER-STRICT"),
            probes=sum(1 for r in rs if r["kind"] == "probe"))
    return per


def findings(rows):
    out = []
    for r in rows:
        if r["verdict"] == "MISSED":
            out.append(OrderedDict(type="miss", documentedExclusion=bool(r["design"]), gate=r["gate"], case=r["base"], mutation=r["mutation"], what=r["what"], applied=r["applied"], design=r["design"]))
        elif r["verdict"] == "OVER-STRICT":
            out.append(OrderedDict(type="over-strict near-miss", documentedExclusion=False, gate=r["gate"], case=r["base"], mutation=r["mutation"], what=r["what"], applied=r["applied"], design=None))
    return out


def build(rows, baselines, sources, out_json, out_md):
    per = summarise(rows); fnd = findings(rows)
    doc = OrderedDict(generated=time.strftime("%Y-%m-%d"), method="factory/tools/mutation-calibration/calibrate.py: each mutation edits a copy of run 01 of real committed/rerun evidence; the verdict is the exit status of `pair.py <case> --recompare <run>` (same gate dispatch as the pipeline)",
                      baselines=baselines, sources=sources, gates=per, findings=fnd, notCalibratedOffline=[dict(what=a, why=b) for a, b in NOT_CALIBRATED], rows=rows)
    Path(out_json).write_text(json.dumps(doc, indent=1))
    L = []
    tot = lambda k: sum(v[k] for v in per.values())
    L.append("# Mutation calibration results\n")
    L.append(f"Generated {doc['generated']} by `factory/tools/mutation-calibration/calibrate.py` (see its README for every mutation). Offline: no capture, no Windows, no Sandbox. "
             f"All {len(baselines)} unmutated base fixtures pass their gates before any mutation is applied. The verdict of every row is the exit status of `pair.py <case> --recompare <run>`.\n")
    L.append(f"**{tot('caught')} of {tot('mutations')} seeded faults caught; {tot('nearMissPassed')} of {tot('nearMisses')} near-misses inside a tolerance passed; {tot('overStrict')} over-strict gates.** "
             f"{tot('missed')} faults were not caught: {tot('missedUndocumented')} with no documented reason (findings A below), {tot('missedDocumentedExclusion')} that a decision or the gate's own contract says is not gated (B below).\n")
    L.append("| Gate | Comparator | Caught / seeded | Missed (undocumented / documented exclusion) | Near-misses passed | Over-strict | Probes |\n|---|---|---|---|---|---|---|")
    for g, v in per.items():
        extra = []
        if v["caughtByAnotherGateOnly"]: extra.append(f"{v['caughtByAnotherGateOnly']} by the case's pixel gate")
        if v["caughtByComparatorCrash"]: extra.append(f"{v['caughtByComparatorCrash']} by a comparator crash")
        L.append(f"| {g} | `{v['comparator'].split(' ')[0].replace('factory/tools/', '')}` | {v['caught']} / {v['mutations']}" + (f" ({'; '.join(extra)})" if extra else "") + f" | {v['missed']} ({v['missedUndocumented']} / {v['missedDocumentedExclusion']}) | {v['nearMissPassed']} / {v['nearMisses']} | {v['overStrict']} | {v['probes']} |")
    L.append("\n`text-origin` is the TextField text-origin and selection-colour gate (decisions 12, 13 and 14, commits ddff82031, 09e184945 and d07df2581 and the y gate of 15 October); it is included. `ime` is the IME range gate of decision 15, new on 15 October; the findings that opened this pass (marked-text range, 2-3 px clock translation, text-origin y, control x, alert default button, text position and colour) are all gated now (decisions 14 to 19).\n")
    A = [f for f in fnd if not f["documentedExclusion"]]; B = [f for f in fnd if f["documentedExclusion"]]
    L.append("## A. Findings: seeded faults no gate caught, with no documented reason\n")
    if not A: L.append("None.\n")
    for f in A:
        L.append(f"- **{f['gate']} / {f['case']} / {f['mutation']}** ({f['type']}): {f['what']}. Applied: {f['applied']}.")
    L.append("\n## B. Faults not caught that a decision or the gate's contract says are not gated\n")
    L.append("Listed so the gaps are visible; nothing here was changed.\n")
    for f in B:
        L.append(f"- **{f['gate']} / {f['case']} / {f['mutation']}**: {f['what']}. Reason: {f['design']}.")
    near_bad = [r for r in rows if r["verdict"] == "OVER-STRICT"]
    L.append("\n## C. Near-misses that failed (over-strict gates)\n")
    L.append("None. Every near-miss placed exactly at or just inside a tolerance (edge-aa 32, hazeTolerance 3, C2 1 px and the spring's 2 px for extent and edges, progress 0.004/0.005, text bbox 1 px, button/list label ink 40, button label centring 3 px, toggle label centring 1 px, row frames 1 px, text-colour 24, text-origin y envelope, semantic bounds 0.05 pt) passed.\n" if not near_bad else "\n".join(f"- {r['gate']} / {r['base']} / {r['mutation']}: {r['applied']}" for r in near_bad))
    pr = [r for r in rows if r["kind"] == "probe"]
    if pr:
        L.append("\n## D. Sensitivity probes (px-edge, rounded stroke, edge-aa<=32, hazeTolerance 0)\n")
        L.append("| Probe | Gate verdict |\n|---|---|")
        for r in pr: L.append(f"| {r['mutation']} | {r['verdict'].replace('probe: ', '')} |")
    L.append("\n## E. Gates and properties not calibrated offline\n")
    for a, b in NOT_CALIBRATED: L.append(f"- **{a}**: {b}")
    L.append("\n## F. Earlier coverage this pass builds on\n")
    L.append("- `factory/VERIFICATION.md`: F8 timing selftest, 15 fault controls on synthetic timing (predates SR1; does not touch the pair.py comparators).")
    L.append("- `factory/pipeline/paired-five-seeded-observations-actual-v4/fault-controls.json`: 10 provenance-receipt faults rejected (receipt gate, not pixels or semantics).")
    L.append("- `factory/tools/test_pair_control_report.py`, `test_pair_semantic_report.py`, `test_pair_textorigin_report.py`: unit tests on synthetic inputs (they passed at 668bab00e; not re-run on 15 October: the workspace hook forbids local test execution); none uses real run evidence, and no test existed for the pixel, text, text-colour, button, list, clock, image or ime gates.")
    L.append("\n## Evidence the fixtures come from\n")
    L.append("| Fixture | Case | Run |\n|---|---|---|")
    for k, v in sources.items(): L.append(f"| {k} | `{v['case']}` | {v['run']} |")
    Path(out_md).write_text("\n".join(L) + "\n")
    return doc
