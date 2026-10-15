# Windows Sandbox worker (factory/tools/sandbox)

A long-lived, minimised Windows Sandbox on the Dell runs a job worker (`guest/guest-worker.ps1`). `client.py` is the Mac-side client (`start` once per day, `sync` after editing guest scripts, `status`, `capture`, `interact`, `command`, `w08`). Jobs: `capture` (PrintWindow captures, used by `pair.py --sandbox`), `command`, `w08`, and the new `interact`. Nothing here opens a window on Adrian's desktop.

## F2: the interaction job (`interact`, added 13 Oct 2026, shared by all round-3 lanes)

`python3 factory/tools/pair.py <case> --runs N --stage S --renderer R --sandbox --steps steps.json` (or put `"steps": [...]` in the case's `pair.json`), or directly
`python3 factory/tools/sandbox/client.py interact <exe> --steps steps.json --runs N --out DIR --renderer DLL`.

Per run the guest launches the host exe (same copy/renderer/lease handling as `capture`), pushes its window to the bottom, runs the steps, then writes into the run's `windows/` folder:
`native-NN.png` (PrintWindow of the main window, as `capture`), `uia-NN.json` (UI Automation tree of EVERY visible top-level window the process owns, including a TaskDialog; per element: name, role, localizedRole, automationId, className, bounds (screen px), enabled, focus, focusable, offscreen, toggle state, value, selected; per window: hwnd, class, title, rect, `client` = [x, y, w, h] screen px of the client area, dpi; plus the `focusedElement` of the process), `steps-NN.json` (what each step did), `uia-NN-<label>.json` / `native-NN-<label>.png` for `dump`/`shot` steps, `done.json`, `host-NN.std{out,err}.txt`.

Steps (JSON list; every step may carry `"target":"dialog"` to address the newest other window the process owns, e.g. a TaskDialog; coordinates are client pixels):

| op | fields | effect |
| --- | --- | --- |
| `key` | `key` (`Tab`, `Enter`, `Escape`, `Space`, arrows, `Home`, `End`, `Backspace`, `Delete`, `F1`..`F12`, a letter or digit, `vk:0x..`), `mods` (`shift`, `ctrl`, `alt`), `input` | WM_KEYDOWN/WM_KEYUP posted to the window. With `mods` or `input:true` the keys go through `keybd_event` after the Sandbox gives the window foreground (posted messages do not move GetKeyState); the host's own foreground guard (`factoryAbortOwnedForeground`) fails such a run, so use it only with a host that tolerates focus |
| `char` | `text` | one WM_CHAR per UTF-16 unit |
| `click` | `x`, `y`, `button` (`left`/`right`), `count` | WM_MOUSEMOVE, then button down/up posted at the client point |
| `ime` | `action` (`compose`, `commit`, `cancel`), `text` | tries `ImmSetCompositionStringW` on the window's input context, then posts `WM_IME_STARTCOMPOSITION`/`WM_IME_COMPOSITION` (`GCS_COMPSTR`/`GCS_RESULTSTR`)/`WM_IME_ENDCOMPOSITION`. **Caveat:** `ImmGetContext` of another process's window returns NULL, so the IMM call is refused and only the posted messages arrive; the step log says `imc=False,imm-accepted=False`. A renderer that reads the composition with `ImmGetCompositionStringW` sees no text. Real composition needs an in-process hook (host side) or hardware |
| `move` | `x`, `y`, `down` | WM_MOUSEMOVE posted at the client point (wParam MK_LBUTTON when `down`): a hover, or a held-button move |
| `drag` | `x0`, `y0`, `x1`, `y1`, `steps` | WM_MOUSEMOVE, left button down at (x0, y0), `steps` WM_MOUSEMOVE with the button held along the line, button up at (x1, y1) (a slider's thumb) |
| `leave` | | WM_MOUSELEAVE posted: the pointer left the window |
| `invoke` | `name` | UIA InvokePattern on the first element of the target window with that Name (dialog buttons) |
| `foreground` | | gives the target window the foreground inside the Sandbox (it is its own desktop). UIA still reports no keyboard focus there (the Sandbox session has no input focus), so focus is gated through app state, not `HasKeyboardFocus` |
| `wait` | `ms` | sleep |
| `dump` | `label` | extra UIA dump |
| `shot` | `label` | extra PrintWindow |

The host's 10 s capture lease still bounds a run: keep step lists short (the guest waits 500 ms before and after the steps; `settleMs`).
The Mac counterpart of the UIA dump is the in-process dump compared by `factory/tools/pair_semantic_report.py` (F3).

Measured limits: a key posted with `PostMessage` reaches a task dialog and its default button runs (Enter); `keybd_event` after `foreground` did NOT reach the dialog in the Sandbox. A TaskDialog is listed by UIA both as its own window and under its owner (the comparator drops the nested copy).

## F3: the semantic comparator (`factory/tools/pair_semantic_report.py`)

`python3 factory/tools/pair_semantic_report.py <case-dir> <runs/ts dir>` compares each run's `windows/uia-NN[-label].json` (this job) with the Mac host's in-process accessibility dump `mac/ax-NN[-label].json` (`factory/tools/mac-ax-dump/AXDump.swift`, compiled into the Mac host when its source mentions `AXDump.`; AppKit/SwiftUI accessibility is enabled in the host process by setting AXEnhancedUserInterface and AXManualAccessibility on its own application object before the hosting view exists, so no AX client API, no other process, no TCC prompt). `pair.py` runs it when `<case>/pair.json` has `semanticGate`; `"pixels": "report-only"` there makes the semantic verdict decide. The field list, scope, phases and role map are documented at the top of the script; unit tests: `cd factory/tools && python3 -m unittest test_pair_semantic_report`.

Long-run W08 retry test: `client.py w08 tier2-feed-down-long --keep-state ...` leaves the SliceApp package NeedsRemediation with the feed down on purpose and writes `C:\sbq\state\longrun-active.json`. While that lock exists every other `w08` / `w08-reset` job is refused (they would destroy the state); `capture`, `clock`, `interact` and `command` jobs are unaffected. `--break-long-run` overrides. Do not change the guest clock (`Set-Date`) while other lanes share the worker: the worker's job timer follows the guest clock and kills the running job. `cmdjob.py script.ps1 --timeout N` runs a command script with a chosen job timeout. Checker and receipt: `qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/`.

## I1: the decode job (`decode`, added 15 Oct 2026, wave 0 image foundations)

`factory/pipeline/blocks-w0-i1/run.py decode --runs N --out DIR [--env NAME=VALUE]` queues a `decode` job (`guest/job-decode.ps1`): the console host `ImageDump.exe` (WIC through `SwiftRightImageIO`) is run N times, each in a fresh process, on the corpus under the mapped `D:\...\.factory-work\hosts\i1\corpus`; per run `run-NN.zip` (`results.json`, `run.bin` = the decoded RGBA buffers; run 1 also the block 35 Swift decoder's `old-*`) lands in the job's `out`, with each `run.bin` SHA-256 in `result.json`. No window, renderer or capture lease; a normal queue entry that waits behind the running job and is unaffected by `longrun-active.json`. `args.env` sets environment variables for the host (e.g. `SWIFTRIGHT_WIC_INTENT`). WIC's JPEG decoder writes libjpeg warnings to stderr for cut files; the job script treats that as output, not as a failure.
