# SR0 R9 native-interaction results

## 2026-10-09, run tag 20261009T144413 (second attempt)

Command: `DESKTOP_LANE_FREE=1 sh probes/sr0-b/native-interaction/scripts/run-native.sh ime-f7 ime-f7live ime-f8 narrator`
Tuple: FreshOnBridge `3593209A49BC540FD0FAB2EC7AD14390A60C9E30042D8B7E23852D48000D68BA`, renderer `C80B9517B044968F3E13EE9D92EEFC8704D000510B9A51B3245C885CE1A3FB30`, base `D:\Claude\sr0s-bridge06b`. Preflight ARTIFACT_OK on both attempts. Input gate: no foreground abort in any check (26, 26, 24, 46 gated key events).

### Attempt 1 (tag 20261009T144302): aborted before any input

All four checks stopped at `schedule-native.ps1` line 17 with "artifact check failed; no task registered". Cause: the harness tested `$LASTEXITCODE -ne 0`, but `verify-artifacts.ps1` returns normally on success, so `$LASTEXITCODE` was `$null` and `$null -ne 0` is true. No scheduled task was registered and no keys were sent. Fix (harness only, not product code): `schedule-native.ps1` line 17 now reads `if (@($verify) -cnotcontains 'ARTIFACT_OK') { throw ... }`. Diagnosed with Astra (gpt-6-astra, high).

### Attempt 2 (tag 20261009T144413): per-check results

| Check | Summary | Result |
|---|---|---|
| ime-f7 | pass=16 fail=1 | FAIL candidate-window-anchored-to-caret. The other 16 PASS, including marked text, conversion to Nihon, commit, Escape cancel, IME restored, caret bounds logged. |
| ime-f7live | pass=16 fail=1 | FAIL candidate-window-anchored-to-caret, same as above. PASS insert-above-fires-mid-real-composition (hook fired, marked 7,3 at release). PASS identity-and-composition-survive-insert-above-real-ime (uuid unchanged, index 1->2, display `Row 2ka???` unchanged). PASS f7live-selftest-verdict (8/8). |
| ime-f8 | pass=14 fail=1 | FAIL candidate-window-anchored-to-caret, same as above. PASS identity-survives-structural-change-mid-composition (Row 7 removed above composing row, uuid unchanged, index 7->6, focus kept). PASS f8-selftest-verdict (13/13). |
| narrator | pass=4 fail=2 fail-not-automatable=2 not-run=2 | See below. |

Evidence for the candidate FAIL (all three IME runs): `no visible top-level window with a class or title containing 'Candidate' was found after Space ... windows new after Space: []`, while the exe logged caret bounds (for example f7: comp1=1,160,828 2x60). The caret anchor is known but the candidate window was not located. This is unresolved: either the driver's window search does not match the real Microsoft IME candidate window, or the candidate window is not drawn or not discoverable. Product anchoring is NOT verified.

Narrator checks:
- provider-focus-event-role-and-id: PASS (focus event type=Edit for Row 3 field, listener in-process).
- provider-value-changed-event: PASS (value=1).
- tab-moves-focus-between-controls: PASS. Focus moved from `row/F0000008-0000-4000-8000-000000000003/field` to `.../000000000005/field` after two Tab presses. The check's detail text says "no Tab traversal exists in the renderer ... product gap", but the result is PASS and the same commit (6b953b5) adds Tab traversal, so that note is stale. Flagged for reconciliation.
- narrator-started-uia-listening: FAIL-not-automatable (another UIA client was already listening before Narrator started).
- narrator-moved-focus-to-delete-button: FAIL. Focus moved among Row 3/4/5 fields but never reached the Row 6 Delete button in 22 commands. Cannot distinguish Narrator ignoring injected (LLKHF_INJECTED) keys from focus-follows-cursor being off, or a product accessibility gap. Not a confirmed product defect.
- narrator-activate-changes-model-state: NOT-RUN (Delete not reached).
- narrator-speech-content: FAIL-not-automatable (speech is audio only; no non-audio log).
- narrator-stopped-and-state-restored: FAIL. Narrator left running at the check (`narrator_processes_left=1`). Narrator registry keys `HKCU:\Software\Microsoft\Narrator` and `...\NoRoam` changed and were not restored (reported only). Caps Lock before=0 after=0.
- narrator-activation-in-runtime-model-state: NOT-RUN (exe saw ax invokes=2, Row 6 removals=1; the driver fallback may have caused the removal).

### Product findings

- Candidate window not located after Space in all three IME runs (FAIL, unresolved, see above).
- Tab moves focus: PASS by evidence. The driver's note claiming no Tab traversal is stale.
- Insert-above during a real composition: composition and identity survived (PASS in F7live). Composition lost on insert-above: not observed.
- Narrator did not reach the Delete button: unresolved (possible product gap or Narrator input-injection limit).

### Cleanup

- Narrator stopped after the run (PID 29232 killed; `narrator_left=0`).
- Caps Lock 0 before and after.
- No SR0 scheduled tasks left (`sr0_tasks=0`), no FreshOnBridge/BridgeSmoke/SR1Gallery processes left.
- Narrator registry keys were changed and are still in that state (not restored; left for a decision).

### Files

- `static-check-20261009T144413.txt`, `preflight-20261009T144413.txt`
- `native-ime-f7-20261009T144413.txt`, `native-ime-f7live-20261009T144413.txt`, `native-ime-f8-20261009T144413.txt`, `native-narrator-20261009T144413.txt`
- Attempt 1 files (`*-20261009T144302.txt`) kept as history.

## Primary cleanup (2026-10-09)

Narrator was not running after the run (0 processes). The changed keys under `HKCU:\Software\Microsoft\Narrator` and `\NoRoam` are Narrator's own first-run defaults (no before-snapshot values were stored by the driver, so exact prior values cannot be restored). The stale `NoRoam\RunningState=1` (Narrator was killed, not exited) was reset to 0. Driver fix needed before the next run: persist the before-snapshot values to the result file and restore every changed value, and stop Narrator with its own exit path before falling back to kill.
