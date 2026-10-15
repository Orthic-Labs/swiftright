# Blocks 37-41, SR1 round 6 (Pulse hub: Slider, onHover/onTapGesture) and the prior-art items

Same shape as `../blocks-26-34` (`make_cases.py` stamps `package/` + `mac-source/` with a byte-identical Witness and a `pair.json` per case through `new-case.py`; hosts are the pinned `shared-*-host` copies, ScalePin decision C12; `python3 run_round6.py <stage> [--renderer WINPATH] [--only substring] [--runs N]` runs every case at N=20 through the Sandbox and appends one record per case to `../consolidation/results.jsonl`). The renderer is the **ABI 0.9** DLL staged as `renderer-0.9-925df9f3` (CI run 38718233163): slider range (decision H1), pointer moves (H3).

| Block | Directory | Cases | Gate |
| --- | --- | --- | --- |
| 37 slider | `swiftui.slider` | values-light, values-dark, disabled-light, disabled-dark, range, widths, over-colour, labels, click-track, drag, keys, disabled-input, value-labels | pixels (edge-aa, haze 1 light, 2 dark) + semantic (UIA role, name, value, enabled, RangeValue value/min/max and SmallChange against the Mac's AXValue/AXMinValue/AXMaxValue and the declared increment) after every event |
| 38 on-hover | `swiftui.on-hover` | rows, adjacent, body-ends-in-modifier (the SwiftCrossUI #789 family), tap-container | pixels after every phase (event squares, hover fills, tap counters); Mac side = witness stand-in (H5, H6) |
| 39 uia-walk | `swiftui.uia-walk` | controls-a, controls-b | semantic tree of every control kind (pixels report-only) |
| 40 ime-traps | `../blocks-6-10/swiftui.ime-traps` | focuschange, hangul, reconvert, badregion | semantic value of both fields + the in-process TextStore script / NSTextInputClient (hardware IME deferred) |
| 41 compat | `swiftui.compat` | id-modifier-order, state-nested-update, task-id, environment-key, any-view | pixels (counts drawn as squares) after every phase |

Mac input is a stand-in everywhere (decisions H5-H6): the offscreen window never takes synthetic mouse or key events. The Mac host (`shared-mac-host`) applies slider clicks, drags and keys through the accessibility value and increment, and calls the witness's `FactoryStandIn` hooks for hover and taps; Windows gets real posted pointer and key messages (`job-interact.ps1`: `move`, `drag`, `leave`, `click`, `key`).

Renderer provenance: `renderer-0.9-925df9f3` is the `render-windows` CI run 38742361678 (headSha 925df9f3ae5edfd91c52a467e498502927b0ab56, conclusion success; artifact `swiftright-render-925df9f3ae5edfd91c52a467e498502927b0ab56`, downloaded and hashed: `swiftright_render.dll` sha256 6b6fc10c81741d27d74075c5fe9ed63a4259e1472ef092764081d2b55924e422). The earlier `renderer-0.9-5c48bb72` came from CI run 38718233163.
