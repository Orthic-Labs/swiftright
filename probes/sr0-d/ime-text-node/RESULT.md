# SR0-D IME text-node probe: result

## Build

- **Verdict: PASS** (compile only; the interactive IME run has not been performed).
- Request: `rr-1791485568673-2875c4c58d248215`, `rightkit remote windows cargo build --release --target x86_64-pc-windows-msvc`, run from `probes/sr0-d/ime-text-node/`.
- Receipt state `SUCCEEDED`, exit code 0, `Finished release profile [optimized]` in 7m 22s.
- Our crate `sr0d-ime-text-node` compiled with no warnings in the receipt tail. The only note is a future-incompat warning from dependency `proc-macro-error2 v2.0.1`.
- No fix iterations were needed (1 of 4 used).
- Exe (receipt `command`, target dir from the broker):
  `D:\.rightkit-managed\rightkit-build-control\ws\23805cb9144c\g\001\target\x86_64-pc-windows-msvc\release\sr0d-ime-text-node.exe`
- The exe's existence on the Windows host has not been independently checked. `scripts/ime-run.ps1` fails fast if it is missing.

## GPUI 0.2.2 mapping: IMM32 message to InputHandler method

Source: crate `gpui-0.2.2` from static.crates.io. Paths below are inside that crate.

| Windows message / condition | GPUI handler (`src/platform/windows/events.rs`) | Calls into `EntityInputHandler` (via `PlatformInputHandler`) |
|---|---|---|
| `WM_CHAR` (non-control char) | `handle_char_msg` 428-432 | `replace_text_in_range(None, ch)` (line 430) |
| `WM_DEADCHAR` | `handle_dead_char_msg` 437-441 | `replace_and_mark_text_in_range(None, ch, None)` (line 440) |
| `WM_IME_STARTCOMPOSITION` | `handle_ime_position` 629-655; `retrieve_caret_position` 616-627 | `selected_text_range(false)`, then `bounds_for_range(selection.range)`, then `ImmSetCompositionWindow` and `ImmSetCandidateWindow` at that point |
| `WM_IME_COMPOSITION`, `lparam == 0` | `handle_ime_composition_inner` 664-672 | `replace_text_in_range(None, "")` (line 670) |
| `WM_IME_COMPOSITION`, `GCS_COMPSTR` | 674-683 | `replace_and_mark_text_in_range(None, comp, caret)`, caret `Some(pos..pos)` from `GCS_CURSORPOS` when set (line 682) |
| `WM_IME_COMPOSITION`, `GCS_RESULTSTR` | 685-690 | `replace_text_in_range(None, result)` (line 688), then returns `Some(0)` so DefWindowProc does not re-insert |
| `WM_KEYDOWN` / `WM_SYSKEYDOWN` while `marked_text_range()` is `Some` | 384-393 | `marked_text_range()` query; if composing, the key goes to `TranslateMessage` and GPUI key callbacks are skipped |

Notes:
- `WM_CHAR` control characters are dropped by `parse_char_message` (`!c.is_control()`, line 1233). Backspace therefore never reaches `replace_text_in_range` through `WM_CHAR`. The probe handles it with a `Backspace` key binding and action, the same way GPUI's `examples/input.rs` does.
- `text_for_range`, `unmark_text` and `character_index_for_point` are marked `dead_code` or `allow(unused)` on the Windows path in `src/platform.rs` (around lines 881-1070). The IMM32 dispatch above never calls them. They are still implemented in the probe, but the interactive run is what would show whether any of them is called.
- `bounds_for_range` is called only through `retrieve_caret_position`, so the candidate window is positioned from the fixed rect the probe returns (logical 320,160, 2x24).

## Probe behaviour (`src/main.rs`)

- `ExternalBuffer { text: String, selection: Range<usize>, marked: Option<Range<usize>> }` is owned by the view. Ranges are UTF-16 code units.
- `ImeProbe` implements `EntityInputHandler` with all seven methods.
- A hand-authored `TextNodeElement` calls `window.handle_input(&focus, ElementInputHandler::new(bounds, view), cx)` in `paint`, like `examples/input.rs`. The window is focused at startup.
- Each handler call logs one `[ime-probe] ...` line to stderr with its args and resulting `text`, `selection16`, `marked16`.
- Thread check: `UI_THREAD` is recorded before `Application::run`, and every handler asserts `current == ui`. A mismatch panics with `called off the UI thread`.
- Gap: the per-line log does not print the thread id. The assertion enforces the UI-thread requirement, but a log line per call does not carry the id. Adding it means one more build.

## Interactive test protocol (desktop, not SSH)

Run `probes/sr0-d/ime-text-node/scripts/ime-run.ps1` from an interactive PowerShell. It writes `D:\Claude\sr0d-ime\stderr.log`, waits for the window to close, then prints the log.

Setup: enable the Microsoft Japanese IME (Settings > Time & language > Language & region > Japanese). Switch to it with Win+Space. Click inside the probe window.

Startup lines, which should appear first:
- `[ime-probe] start ui_thread=...`
- `[ime-probe] window focused at startup`
- `[ime-probe] first paint: ... focused=true handle_input_registered=true`

| # | User action | Expected log lines | Proves |
|---|---|---|---|
| 1 | IME off (A mode). Type `a` | `replace_text_in_range args_range16=None target16=0..0 text="a"`, state `text="a" selection16=1..1 marked16=None` | Committed text via WM_CHAR |
| 2 | Backspace | `action=Backspace caret16=1 delete16=0..1`, then `text=""` | Delete path through the InputHandler |
| 3 | Type `a`, then Ctrl+A, then Backspace | `action=SelectAll -> selection16=0..1`, then `action=Backspace selection-nonempty`, then `text=""` | Selection query and replacement of a selected range |
| 4 | IME on (`あ` mode). Type `n` | `selected_text_range ... -> 0..0`, then `bounds_for_range args16=0..0 ... -> fixed=...320,160...`, then `replace_and_mark_text_in_range ... new_text="ん" ... marked16=Some(0..1)` | Candidate position query on WM_IME_STARTCOMPOSITION; marked text |
| 5 | Type `nihon` | Further `replace_and_mark_text_in_range` lines, the marked range growing to `0..3` for `にほん`, and `marked_text_range -> Some(...)` on keydowns | Composition updates and marked-text query during composition |
| 6 | Space (candidates), Enter (commit) | `replace_and_mark_text_in_range ... new_text="日本"`, then `replace_text_in_range args_range16=None target16=<marked> text="日本" ... marked16=None` | GCS_RESULTSTR commit replaces the marked range |
| 7 | Type `a` after the commit | `replace_text_in_range ... text="a"` appended after 日本 | Caret was left at the end of the committed text |
| 8 | Type `nihon`, then Escape | `replace_text_in_range ... text=""` (lparam==0 path, if the IME sends it) | Cancelled composition clears the marked range |

Visual check: the candidate list should open at logical 320,160 (scaled by display DPI) in the probe window, which is where the fixed rect points.

Pass criteria: every row above produces its expected lines, the process exits with code 0 after the window is closed, and there is no `called off the UI thread` panic.

## Not yet verified

- Interactive run: not performed. The IMM32 paths above are read from source only.
- The `ImmSetCandidateWindow` position on the real desktop.
- Whether any of `text_for_range`, `unmark_text` or `character_index_for_point` is called by the Microsoft IME.

## Interactive result (2026-10-09, Microsoft Japanese IME, hand-typed on the Dell)

Log: [`evidence/stderr-2026-10-09.log`](evidence/stderr-2026-10-09.log), re-read from the host by the primary session.

| Requirement | Result | Evidence |
|---|---|---|
| Committed text (English, WM_CHAR) | PASS | `replace_text_in_range … text="a"`; Backspace and Ctrl+A+Backspace update buffer & selection |
| Marked text during composition | PASS | `replace_and_mark_text_in_range` grows marked16 15..16 → 15..21 on the external buffer |
| Commit from candidate list | PASS | `replace_text_in_range target16=15..21 text="ありがとうございます。"` → marked None, selection 26..26 (UTF-16 correct) |
| Space conversion | PASS | `replace_and_mark_text_in_range target16=32..35 new_text="日本"`, then Enter commits `replace_text_in_range 32..34 text="日本"` |
| Escape-cancel composition | PASS | `replace_text_in_range target16=34..37 text=""` clears marked にほｎ, selection 34..34 |
| Candidate-window placement query | PASS | `bounds_for_range` called at each composition start; IME list appeared at the probe's fixed rect (320,160), not the caret, as designed |
| IME-off Space | PASS | U+3000 inserted via `replace_text_in_range` |
| Calls on UI thread | PASS | No off-thread assertion fired |

Injected input limitation: Unicode-packet (VK_PACKET) keystrokes bypass IME composition. Automated IME fixtures must send virtual-key input from the interactive desktop session.

Caret-anchored candidate placement moves to SR0-B, where `bounds_for_range` returns real caret geometry from Swift-owned text runs.
