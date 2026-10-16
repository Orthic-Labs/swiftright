# Pulse SwiftUI hub on Windows through SwiftRight: porting map

Date: 15 October 2026. Requested by Pulse Swift. Inputs: Orthic-Labs/pulse code `bd6bd3df` (main `d05a4631`), CI run 38646146750 artifact `qa-evidence-xcode-27-1`. SwiftRight stage `8bf89d2dc-aa6cd909` (round-4 blocks 21-25; not the newer HEAD). Probe sources: `probes/pulse-hub/`. Pulse's own code is not committed here: `probes/pulse-hub/fetch-pulse.sh` takes it from SHA `bd6bd3df`.

## Verdict

- **Compile: no stock build, a small gap list.** `RightKitHub`, `RightKitEngine`, `RightKitHubQA`, `PulseHub` and `PulseHubFixtures` compile for Windows (toolchain 6.4.0, language mode 5 and 6) once **20 gaps** are closed: 19 SwiftUI API gaps (table A) and one Foundation gap that is Pulse's, not SwiftRight's. First pass without any stub: **237 unique compiler errors**; after layer-1 stubs 13; after layer-2 stubs 6; the final build has 0 errors. Closing them was done by probe-only stubs (`probes/pulse-hub/shim/Stubs.swift`), a four-item runtime patch copy (`runtime-patch/ProbePatch.swift`) and one source bypass (B1). The 20 gaps are small: 17 of them are one-line API shapes.
- **Render: current state, no probe patch.** At Pulse `906d5192` (round 5) all 12 sections render in light and dark through the product's own paint and text path (24 of 24 pictures). Round 6 at `3e8b6b29` repeats that with Pulse's PulseFit workarounds on and off. The 14 patches in table B were the round-4 state and are no longer used. The pictures are static first frames (nothing clicked, typed or scrolled), single full-window captures, and not pixel-comparable to the Mac: fonts are approximated, and several rows truncate that do not on the Mac. Apps icons: `canImport(SwiftRightHost)` is now true in RightKitHub (round 7, section 0); the icons still draw as one generic glyph per row, not app icons.
- **Effort: about 17 agentic hours of critical path for the gaps as grouped below (16 blocks at the measured round-4 rate of 1.08 h per block, one lane), 36 h at the measured round-3 end-to-end rate.** Not included: Oracle review (round 4 has none), a fit pass over the 12 sections after the blocks land, and anything interactive. Arithmetic in section 4.

## 0. Round 9 result (16 October): Pulse 7ef8d10ab fixes the decode; wrapper removed

- **Pulse SHA:** `7ef8d10ab` (Pulse main, "SwiftUI hub QA: decode images on Windows"). `QAServices.decodeImage` now calls `ImageDecoder.decode` on Windows, and the Chess Night fixture icon is its own PNG (167 bytes, not a copy of Pixel Forge's). Fetched read-only with `PULSE_SHA=7ef8d10ab fetch-pulse.sh`; assembled with `R5=1 assemble.sh`; the Pulse repo is untouched.
- **Probe:** the round-8 decode wrapper is moved aside to `probes/pulse-hub/retired/ProbeHubServices.swift`, and `host/HubRoot.swift` again uses `RecordingPlatformServices()`. Built on the Dell with `buildhost.ps1`, 0 errors. Captured through the sandbox worker (frames 10 light, 11 dark).
- **Result:** the light and dark pictures show real icons for Studio Video, Notebook Pro, Pixel Forge, Sheets and Terminal Plus (five distinct icons). Mail Relay and Safari show the neutral glyph. Chess Night and Tiny Notes are below the fold in this frame and are not visible in these pictures, so Chess Night's icon is verified only at the fixture-byte level (distinct PNG, distinct hash), not on screen. No host errors (`HOST_RENDER_ERROR`, `HOST_EXCEPTION`) in the logs.
- **Pictures:** `docs/pulse-hub-windows/apps-light.png` and `apps-dark.png`. Host logs: `docs/pulse-hub-windows/host-logs/round9-apps/`.

## 0. Round 8 result (16 October): app icons drawn, cause was Pulse's recording services

- **Root cause (evidence):** the icon bytes arrive and decode. `RightKitHubQA/RecordingPlatformServices.decodeImage` (Pulse `3e8b6b29`, `swift/RightKitHub/Sources/RightKitHubQA/QAServices.swift`) is `#if os(macOS) … #else return nil`. Off macOS it returns nil and never reaches the protocol default (SwiftRightHost `ImageDecoder`). `AppsSection.preparedView` preloads with those services, so every row fell back to the glyph. The timing is not the cause: `load(live:false)` awaits `requestIcons(waiting: true)` before the preload, so the icons are in place before the frame is taken. The decoder is not the cause: `PNGDecoder.decode` compiled on the Mac returns 56x56 for all six fixture PNGs.
- **Probe fix (probe-side, Pulse untouched):** `probes/pulse-hub/host/ProbeHubServices.swift` delegates every member to `RecordingPlatformServices` except `decodeImage`, which calls `ImageDecoder.decode(_:maxPixel:)`. `HubRoot.swift` uses it. The probe logs one `PROBE_DECODE ok|fail` line per call (temporary).
- **Evidence:** `docs/pulse-hub-windows/host-logs/round8-apps/` (light and dark): five `PROBE_DECODE ok 56x56` lines per run, all before `HOST_HUB prepared`, no `HOST_RENDER_ERROR` or `HOST_EXCEPTION`.
- **Pictures:** `docs/pulse-hub-windows/apps-light.png` and `apps-dark.png` (single captures, 2250x1500). Studio Video, Notebook Pro, Pixel Forge, Sheets and Terminal Plus draw their own icons. Mail Relay and Safari (and Tiny Notes, below the fold) keep the glyph, as the fixture has no icon for them.
- **Fixture finding (Pulse's, not fixed here):** Pixel Forge's and Chess Night's fixture PNGs are byte-identical (md5 `4f52f7e4…`), so they draw the same picture and the cache decodes them once.
- **Pulse-side requirement:** `RecordingPlatformServices.decodeImage` should answer with the protocol default on non-macOS (remove the `#else return nil`), or the Windows platform services must own decoding. No `SHGetFileInfo` or `IShellItemImageFactory` member is needed for these fixture icons; a real Windows app icon source is a separate requirement for the live engine.

## 0. Round 7 result (16 October): canImport true, Apps re-captured

- **canImport(SwiftRightHost), RightKitHub target: before `false`, after `true`.** Change: `probes/pulse-hub/Package.swift` adds `.product(name: "SwiftRightHost", package: "SwiftRightHost")` to the RightKitHub target. The manifest is Windows-only (stage paths with backslashes), so no platform condition was needed. Measured on the Dell at Pulse `3e8b6b29`, stage `3d3c6f5c2-0a0d1f39`, with the canImport probe (`probes/pulse-hub/canimport/RightKitHub-canimport-probe.swift`) mounted inside RightKitHub. Both builds: 0 errors. Logs: `probes/pulse-hub/canimport/results/before-RightKitHub.log` (`false`) and `after-RightKitHub.log` (`true`).
- **Apps, light and dark:** `docs/pulse-hub-windows/apps-light.png` and `apps-dark.png` (single captures, 2250x1500). FactoryProbe was rebuilt with the new manifest and captured at frames 10 and 11 through `setframe.sh` and `render-frame.py`. Host logs: `docs/pulse-hub-windows/host-logs/round7-apps/`. No `HOST_RENDER_ERROR` and no `HOST_EXCEPTION`.
- **What the Apps icons look like now:** each of the nine app rows (Studio Video, Notebook Pro, Pixel Forge, Sheets, Terminal Plus, Mail Relay, Safari, and two more below the fold) has a small rounded tile with the same generic document glyph. The glyph does not vary by app, so the rows look like placeholders, not app icons. The canImport fix is necessary but not sufficient. The app-icon data path (`HubImage` and `image(fitting:)`) was not inspected further in this round, and there is no Mac icon reference here to compare against.
- **Round-6 host logs:** `docs/pulse-hub-windows/host-logs/round6/`, 54 job folders staged from the Dell sandbox results (the 48 round-6 captures plus blank-frame retries). None has `HOST_RENDER_ERROR` or `HOST_EXCEPTION`.
- Not re-captured this round: the other ten sections and the `nofit/` pictures. They are the round-6 pictures.

## 0. Round 6 result (16 October): Text in priority groups, Pulse at 3e8b6b29, PulseFit on and off

Pulse at `3e8b6b29` (`PulseFit.swift` present), SwiftRight stage `3d3c6f5c2-0a0d1f39` (HEAD of the layout-rules lane). Probe package: `probes/pulse-hub/` (`fetch-pulse.sh`, `assemble.sh` with `R5=1`), built on the Dell with `buildhost.ps1`: **0 errors, exit 0** for `FactoryProbe` in both variants. The renderer is `renderer-0.7-baseline-22ad719b` (sha `82513ae0`), the one the case gates use. Pictures: `docs/pulse-hub-windows/<section>-<scheme>.png` (Pulse's workarounds **on**) and `docs/pulse-hub-windows/nofit/` (**off**: `PulseFit.swift` evaluated as on the Mac, in the fetched copy only; Pulse is not edited). Each picture is a full-window PrintWindow of one launch; each launch was its own Sandbox job with the frame counter set first, because a shared job launched frames out of order (run 2 reported frame 2, run 3 frame 1). Blank (white) first frames were retried at a 15 s wait; the final set has 24 distinct pictures per variant and every picture's host log names the section it shows.

- **Layout rules (block 27, G15):** closed for Text. The eight paired text cases pass the block gate at N=20 on `3d3c6f5c2-0a0d1f39` (text-labels, text-priority, text-three-groups, text-spacer, hub-rows, text-zero-proposal, text-fixed-size, system-font line-limit-two). Measured rules: L1-L8 in `docs/sr1-decisions.md`.
- **canImport(SwiftRightHost):** **false** in RightKitHub in our build. Measured with a two-target probe package on the Dell (same stage): a target that depends on `SwiftRightRuntime` only reports `false`, a target that depends on `SwiftRightHost` reports `true`. RightKitHub's probe target does not depend on `SwiftRightHost`, so `HubImage` has no backing and `image(fitting:)` returns nil. Consequence, seen in the pictures: the Apps section shows generic placeholder tiles, not the app icons. Fix on either side: add the `SwiftRightHost` product to the RightKitHub target (probe) or the Pulse package (the Windows host product), then re-measure.
- **PulseFit.swift:** with the workarounds off, seven of the twelve sections draw differently (activity, storage, monitor, apps, chat, accounts, and appearance dark); the other five are identical. This round does not show what the Mac does with those sections; the seven need a per-section check before any of the Windows priorities or lengths is removed.

| Section | Compiles | Renders light, dark (on) | Pictures differ with PulseFit off |
| --- | --- | --- | --- |
| overview | yes | yes, yes | no |
| activity | yes | yes, yes | yes, yes |
| storage | yes | yes, yes | yes, yes |
| cleanup | yes | yes, yes | no |
| monitor | yes | yes, yes | light yes; dark only a 30 px band |
| apps | yes | yes, yes (icons are placeholders: canImport false) | yes, yes |
| chat | yes | yes, yes | light yes; dark yes |
| permissions | yes | yes, yes | no |
| accounts | yes | yes, yes | yes, yes |
| appearance | yes | yes, yes | light no; dark only a 10 x 68 px area |
| notifications | yes | yes, yes | no |
| general | yes | yes, yes | no |

No `HOST_RENDER_ERROR` and no `HOST_EXCEPTION` in any of the 48 captures. Not verified this round: clicking, typing, scrolling, the `.task` path, and pixel comparison with the Mac.

## 0. Round 5 result (15 October, later the same day): the gaps are closed

Pulse at `906d5192` (Pulse main, parity pass), SwiftRight stage `795d1644a-38920803`. **No stubs, no source bypass, no runtime or host patch**: the probe package is Pulse's sources untouched plus the SwiftUI re-export shim and a `Bundle.module` shim (probe packaging: PulseHub's Tanker resource bundle is not bundled, licence unconfirmed; `probes/pulse-hub/r5/`; assemble with `PULSE_SHA=906d5192 R5=1`). All five modules (`RightKitEngine`, `RightKitHub`, `RightKitHubQA`, `PulseHub`, `PulseHubFixtures`) and the `FactoryProbe` host compile for Windows with 0 errors, and **all 12 sections render in light and dark: 24 of 24 pictures** through the product's own paint and text path (`docs/pulse-hub-windows/<section>-<scheme>.png`, last panel; the Tauri and Mac panels are the earlier CI artifact and predate Pulse's parity pass). No `HOST_RENDER_ERROR`, no ellipsis-only fallback, no opaque-black rect in any section. Honest limits: the pictures are static first frames (nothing clicked, typed, scrolled; the live `.task` path never ran); nothing was compared pixel by pixel with the Mac (fonts differ, decision 2); four capture runs report `GetClientRect failed` but produced valid pictures, and a first-launch Sandbox capture occasionally comes out blank (the Activity page needs a 15-20 s wait): the pictures were re-taken until none was blank.

### Compile gaps (table A)

| # | API | Status |
|---|---|---|
| G01 | `AnyView`, `.id` | closed (block 26, F12) |
| G02-G06 | `accessibilityElement`, `Value`, `AddTraits`, `Hint`, `Hidden` | compile and behave (block 32, F10); hint not published (no ABI field), value on a Text and the header/link traits not delivered |
| G07 | `Text(verbatim:)` | closed (block 26) |
| G08 | `State(initialValue:)` | closed (block 26) |
| G09, G10 | `Color.clear`, `Color.opacity` -> `Color` | closed (blocks 26, 31) |
| G11 | single-child `ViewBuilder` identity | closed (block 26) |
| G12 | `VerticalAlignment.firstTextBaseline` / `lastTextBaseline` | closed (block 33, F3) |
| G13, G14 | `Font.Weight.heavy` (nine weights), `Font.width` | closed (block 28, F1); `width` carried, not drawn |
| G15 | `layoutPriority` | closed for Text children (round 6: eight text cases pass N=20, decisions L1-L8) |
| G16, G18 | `View.id`, `ViewModifier` | closed (block 26) |
| G17 | `TextField(axis:)` | compiles and is the single-line field (block 34, F9); growth over lines not delivered |
| G19 | `Scene` / `WindowGroup` | shapes only (compile) |
| G20 | `RelativeDateTimeFormatter` | fixed on Pulse's side (`#if os(Windows)`, f8460ed5) |

### Render gaps (table B)

| # | Gap | Status |
|---|---|---|
| R1 | SF Symbols | closed: 60 names mapped to Segoe Fluent Icons, font-sized regular/semibold/bold painting from Mac-measured sizes (block 29, F5-F8, F14-F16); shapes ungated, 12 weak mappings |
| R2 | system fonts, text styles | closed (block 28, F1) |
| R3 | `TextMeasureError.description` recursion | fixed first (c5898d25e), unit test |
| R4 | `lineLimit(1)` where nothing fits | ellipsis alone instead of a refusal (F2); macOS clips instead |
| R5 | run lookup refusal | a measurement within 1 px of the bounds is the run (F2) |
| R6 | identifiers over 256 bytes | hashed to fit (F2) |
| R7, R8 | large radii, zero-size and oversize shapes | closed: Apple's large-radius path family, exact bands, no-area shapes draw nothing (block 30, F4); a stroked pill not delivered; edge-AA on flat shoulders differs from Apple's by a named tolerance |
| R9 | measurement cache bound | 8192 |
| R10 | dark `Divider` | closed (block 31, F13) |
| R11 | `Button` under opacity / empty frame | plain and borderless Buttons paint; bordered under opacity still refused |
| R12 | transparent fills painted black | closed (block 31; the host's alpha path was later reworked by wave 0 T0, which measured the unpatched renderer draws an alpha-0 rect as nothing) |
| new | a transaction over 4096 upserts (Monitor 4718, General 4186 nodes) was refused with `SWR_E_TOO_LARGE` | closed: sent as consecutive transactions in tree order (`BridgeWindow.commit`) |
| new | dark bordered/prominent/disabled Buttons drew as white blobs | closed (block 36, F13) |
| new | Windows `Image` from PNG/ICO bytes | closed for PNG/ICO by the Swift decoder (block 35, F17-F22); wave 0 I1's WIC/ImageIO service is behind `ImageDecoder.backend = .system` |

### Per section at Pulse 906d5192

"Compiles": the section's module is part of the building package. "Renders": a frame was drawn light and dark with no refusal and no probe patch. Node counts are the transaction size (the Monitor and General pages exceed the renderer's 4096-node transaction limit and are sent in two).

| Section | Compiles | Renders (light, dark) | Nodes (images) | Truncation searches |
|---|---|---|---|---|
| overview | yes | yes, yes | 3333 (82) | 249 |
| activity | yes | yes, yes | 2637 (245) | 89 |
| storage | yes | yes, yes | 1096 (74) | 204 |
| cleanup | yes | yes, yes | 1079 (59) | 129 |
| monitor | yes | yes, yes | 4718 (118) | 389 |
| apps | yes | yes, yes (placeholder icons until the PNG decode is wired on the Pulse side) | 1143 (75) | 194 |
| chat | yes | yes, yes | 877 (54) | 144 |
| permissions | yes | yes, yes | 503 (25) | 66 |
| accounts | yes | yes, yes | 879 (61) | 150 |
| appearance | yes | yes, yes | 1747 (118) | 208 |
| notifications | yes | yes, yes | 930 (58) | 94 |
| general | yes | yes, yes | 4186 (273) | 313 |

Remaining differences visible in the pictures: Segoe UI is 5-10 % wider than SF, so some `lineLimit(1)` labels truncate that do not on the Mac; the display font (Tanker) is its system fallback; the glyph shapes of the symbols are Segoe Fluent's. Not verified: clicking, focus, typing, `Toggle`, `Menu`, scrolling, `.task` refresh, resize, animations, the accessibility tree of the hub, DPI other than 2.5.

### Measured effort (agentic wall clock, one session beside the closure and wave-0 sessions; 15 October 06:55 to 14:15, 7.3 h)

Per block: authoring (runtime, tests, cases, Mac references, N=1 on the Windows Sandbox), without the N=20 queue wait: 26 text-views 0.25 h, 27 layout-priority 0.4, 28 system-font 1.3, 29 system-symbols 1.5 (one subagent, in parallel), 30 continuous-shape-large 1.2 (the anti-aliasing investigation was 0.4), 31 paint-states 0.5, 32 accessibility 0.6, 33 baseline-alignment 0.7, 34 textfield-axis 0.2, 35 image-data 1.3 (subagent, in parallel), 36 button-dark 0.8; the crash fix 0.02; the hub probe, doc and bookkeeping about 2 h. Sum of block authoring 8.8 h over 7.3 h wall (two subagents ran in parallel). N=20 captured 57 cases at about 6.5 min each (390 s mean) in the shared Sandbox queue, overlapping the authoring. **Per block: 0.8 h of authoring mean (11 blocks), 0.66 h wall per block including everything**, against the planned 1.08 h per block and 16 blocks (17 h): the blocks that were API shapes cost 0.2-0.6 h, the two that needed measurement campaigns (fonts, symbols) and the shape anti-aliasing 1.2-1.5 h, so the estimate of two slow families (symbols, fonts) held and the rest were cheaper than round 4's rate. The split into 11 blocks instead of 16 grouped the gaps as the plan said. A fit pass over the 12 sections and anything interactive are still not done.

## 1. How it was compiled and rendered

- Windows, Dell, headless `swift build` and `swiftc` only; stage `8bf89d2dc-aa6cd909` is read-only and untouched. Probe package `PulseHubProbe` has one target per Pulse module, a target named `SwiftUI` (shim: `@_exported import SwiftRightRuntime`, `Foundation`) so Pulse's `import SwiftUI` resolves, and the C module `CRightKitEngine` with `rkp_*` and `rke_install_engine` link stubs (`stubs/rkp_stubs.c`; the Rust staticlib is not built).
- Error collection: `tc.ps1` type-checks one whole module in one `swiftc -wmo` run with `-experimental-allow-module-with-compiler-errors`, so dependent modules are checked past the errors; `iter.ps1` loops the four modules. Result lists: `docs/probes/evidence/pulse-hub-compile-errors.txt` (passes tc1, tc2, tc3). Counts are a lower bound per pass (a result-builder body reports its first error only, hence the layered passes). The final truth is a real per-file `swift build` of all five modules: 0 errors (`run.ps1`).
- Render: the executable `FactoryProbe` (`host/main.swift`, a copy of the case host in `blocks-17-20` with the hub as the root view) builds the section with `preparedView`, wraps it in `HubShell(... initialLifecycle: .ready, footer: PulseSidebarFooter())` at 900x600 and runs through the product paint path and the renderer DLL (`inputs/renderer/swiftright_render.dll`, ABI 0.6). Capture is the Sandbox `interact` job (PrintWindow, owned window, no desktop window): 24 launches, a counter file picks section and scheme. Scale was 2.5 (Sandbox DPI 240), so 2250x1500 pixels; the panels below are downscaled to 900x600. One Sandbox queue slot per job; the W08 long-run lock and other lanes' jobs were not touched.
- Not done: no Mac build, no Mac GUI, no Windows desktop window. The Mac and Tauri panels are the CI artifact's PNGs.

## 2. Gaps

### A. Compile gaps (what stops `swift build`), ranked by sections blocked, then use sites

"Sections blocked" is how many of the 12 sections draw through a file that contains the site (the shell, sidebar, header and toast files block all 12). Sites are regex counts over Pulse's source, so they are exact, unlike the compiler list. Fix: S = probe stub (compile only, no behaviour), R = working in the runtime patch, B = source bypass.

| # | Missing API | Sites | Files | Sections | First sites | Probe fix |
|---|---|---|---|---|---|---|
| G07 | `Text(verbatim:)` | 241 | 29 | 12 | HubStates.swift:21 | S |
| G01 | `AnyView` (and `.id` on it) | 41 | 12 | 12 | HubSection.swift:40; every `*Section.swift` makeView | R (transparent container) |
| G09 | `Color.clear` | 13 | 9 | 12 | HubSidebar.swift:154, HubToast.swift:164, HubCard.swift:166 | R |
| G08 | `State(initialValue:)` | 12 | 10 | 12 | HubShell.swift:41, 58 | S |
| G03 | `accessibilityValue(_:)` | 10 | 9 | 12 | HubSidebar.swift:196, HubBarChart.swift:183 | S |
| G11 | `ViewBuilder.buildBlock(_:)` returning its single child (the runtime returns `TupleView<C>`; breaks `Trailing == HubNoTrailing`) | 8 | 4 | 12 | HubHeader.swift:47, HubShell.swift:228, HubCard.swift:173 | R |
| G13 | `Font.Weight.heavy` (the runtime enum has four cases) | 2 | 1 | 12 | PulseTheme.swift:23, 67 | S (maps to bold) |
| G14 | `Font.width(_:)` | 1 | 1 | 12 | HubTheme.swift:296 | S |
| G16 | `View.id(_:)` | 1 | 1 | 12 | HubShell.swift:178 | S |
| G18 | `ViewModifier` + `Content`, `.modifier(_:)` | 1 | 1 | 12 | HubConfirm.swift:5 | S |
| G20 | `RelativeDateTimeFormatter` (not in Foundation on Windows; Pulse's, not SwiftRight's) | 1 | 1 | 12 | PulseFormat.swift:18 | B1 |
| G10 | `Color.opacity(_:)` returning `Color` (the runtime's is the View modifier, so `fill(Color.black.opacity(..))` fails) | 3 | 2 | 11 | HubLayered.swift:45, ChatView.swift:143 | R |
| G04 | `accessibilityAddTraits(_:)` | 11 | 10 | 10 | HubChoiceList.swift:64, SettingsUI.swift:400 | S |
| G02 | `accessibilityElement(children:)` | 9 | 8 | 9 | HubBarChart.swift:181, HubProgressBar.swift:30 | S |
| G12 | `VerticalAlignment.firstTextBaseline` | 11 | 4 | 7 | MonitorView.swift:111, OverviewView.swift:507, SettingsNearbyViews.swift:381 | S (maps to center) |
| G17 | `TextField(_:text:axis:)` | 2 | 2 | 6 | ChatView.swift:405, SettingsLauncherViews.swift:469 | S |
| G05 | `accessibilityHint(_:)` | 4 | 2 | 5 | SettingsNearbyViews.swift:304, SettingsAccountsPage.swift:228 | S |
| G15 | `layoutPriority(_:)` | 2 | 2 | 2 | OverviewView.swift:530, SettingsAccountsPage.swift:441 | S |
| G06 | `accessibilityHidden(_:)` | 1 | 1 | 1 | SettingsAppearancePage.swift:166 | S |
| G19 | `Scene` / `WindowGroup` (`HubScene.swift`, the app's scene helper; no section draws through it) | 2 | 1 | 0 | HubScene.swift:26 | S |

Also seen and not gaps: the runtime's `View`/`ViewBuilder` are `@MainActor`, so a type-erased `AnyView.init` had to be `nonisolated`; `TextField`, `@Observable`, `.task`, `.toggleStyle(.switch)`, `Font.system(size:weight:)`, `lineLimit`, `Layout` all compiled (the lint's "unproven" list compiles, `layoutPriority` is the only one of it that does not). A language-mode 6 type-check shows the same 6 residual errors as mode 5. Stubs make accessibility, `.id`, `ViewModifier`, `layoutPriority`, baseline alignment and `axis:` compile and do nothing, so those behaviours are untested here.

### B. Render gaps (what stops a picture), found by running it

Each row is a refusal or defect in the product's text, paint or bridge path that ended the first frame; the probe patch is in `runtime-patch/patch_host.py` (applied to a copy of the stage). "Pixel" says whether the patch changes what is drawn.

| # | Gap | Sections hit | What the product does today | Probe patch (pixel?) |
|---|---|---|---|---|
| R1 | **SF Symbols**: the shipped table has 1 symbol (`star.fill`); the hub draws 38 distinct names (`checkmark.shield`, `chevron.right`, `internaldrive`, `gearshape` ... full list in `HOST_` logs); the painter also refuses any symbol that is not `resizable().scaledToFit()` | 12 (14-21 symbols each) | `HostPaintError.systemImageContractMismatch`, run ends | P3: transparent rect, intrinsic 16x16 (**yes: no icons**) |
| R2 | **Text fonts**: only the body font and bundled `Font.custom` are measured; `Font.system(size:weight:)` (89 sites) and every text style throw `unsupportedFont`; `lineLimit` other than 1 throws; an unbundled `Font.custom` (Tanker) throws | 12 (6-12 non-body fonts each) | `TextMeasureError`, run ends | P2: body family at the requested size, weights 400-700 (**yes: Segoe UI, approximate heights**) |
| R3 | `TextMeasureError.description` recurses into itself (`"TextMeasure: \(self)"`): the first measurement failure overflowed the stack (0xC00000FD) instead of reporting it | 12 | a silent crash | P1 (no) |
| R4 | `.lineLimit(1)` text offered a width where not even one character and an ellipsis fit throws `noCandidateFits`/`multilineWithoutBound` | 12 (flexible rows) | run ends | P7: unconstrained measurement (**yes: overflow instead of truncation**) |
| R5 | Measured-run lookup refuses text whose resolved bounds differ from its measurement (`measuredRunGeometryMismatch`, `ambiguousMeasuredRun`) | seen in storage, apps, appearance | run ends | P5: closest run (**yes**) |
| R6 | Node identifiers over 256 UTF-8 bytes (the hub's tree reaches 402) make `swr_commit` return `SWR_E_TOO_LARGE`; the first Overview commit failed | 12 | run ends | P6, P6b: prefix + hash (no) |
| R7 | Continuous `RoundedRectangle` radius above `min(w,h)/(2*extent)` is rejected (`unsupportedRadiusExtent`); the hub's pill radius is 99 | 12 | run ends | P4: clamp (**yes: pills are not SwiftUI's**) |
| R8 | Continuous shape raster limits: work limit 2,000,000 px (a card at 2.5x), pixel limit 4 Mpx, and a zero-size shape throws `continuousShapeRasterInput(1)` (SwiftUI draws nothing) | storage, cleanup, apps (work limit); apps (16 zero-width bars), general (22 over the pixel limit) | run ends | P11 raise limit (no), P14 skip the shape (yes) |
| R9 | Text measurement cache bound 256 distinct strings (`measurementCacheBound`) | monitor, appearance, general (up to 910 measurements) | run ends | P10: 16384 (no) |
| R10 | Dark `Divider` refused ("dark appearance not measured") | activity, permissions, accounts, notifications (dark) | run ends | P12 (**yes: light divider colour**) |
| R11 | `Button` with opacity, a foreground style on a bordered look, or an empty frame refused | chat, apps | run ends | P13 (**yes**) |
| R12 | Fully transparent fill (`Color.clear`, `Color.black.opacity(0.001)`, the hit area under every plain Button) reaches the renderer as **opaque black**; root cause not isolated (the colour is correct at the runtime: `rgba(0,0,0,0.001)`), 18 rects on Overview | 12 | black bars under sidebar rows and card headers | P8 (alpha 1/255) did not remove them; P9 in the host drops opaque-black rects (**yes**) |

Per-section first blocker when only P1-P9 were applied (an intermediate run, 7 of 24 pictures): overview (both), and the light scheme of activity, permissions, accounts and notifications rendered; the dark scheme of activity, permissions, accounts and notifications stopped at R10; storage, cleanup and apps (both) at R8; monitor, appearance and general (both) at R9; chat (both) at R11. Unpatched, every section stops earlier, at R2.

## 3. Per-section render status

Pictures: `docs/pulse-hub-windows/<section>-<scheme>.png`, one full-window capture per section and scheme: 2250x1500 px (the 900x600 window at scale 2.5). No Mac or Tauri panel is in the picture. The Mac reference is not in this repository (the round-6 Mac panels came from CI artifact `qa-evidence-xcode-27-1`, which is not kept here). "Compiles" is true for all 12 (the sections share one module). "Renders" means a frame was drawn and the host log has no render error, not that it matches the Mac. The "Patches that fired" column is round-4 data from the 14-patch probe, which later rounds do not use.

| Section | Compiles | Windows light | Windows dark | Patches that fired in this section (from the host logs) | Pictures |
|---|---|---|---|---|---|
| overview | yes | picture | picture | symbols 19, hit-area bars | [light](pulse-hub-windows/overview-light.png), [dark](pulse-hub-windows/overview-dark.png) |
| activity | yes | picture | picture | symbols 14, dark divider | [light](pulse-hub-windows/activity-light.png), [dark](pulse-hub-windows/activity-dark.png) |
| storage | yes | picture | picture | symbols 20, run mismatch 1, raster work limit | [light](pulse-hub-windows/storage-light.png), [dark](pulse-hub-windows/storage-dark.png) |
| cleanup | yes | picture | picture | symbols 17, raster work limit | [light](pulse-hub-windows/cleanup-light.png), [dark](pulse-hub-windows/cleanup-dark.png) |
| monitor | yes | picture | picture | symbols 16, 306 text measurements, cache bound | [light](pulse-hub-windows/monitor-light.png), [dark](pulse-hub-windows/monitor-dark.png) |
| apps | yes | picture | picture | symbols 16, 16 zero-size shapes skipped, run mismatch 2, `lineLimit(n>1)` 3, Button style | [light](pulse-hub-windows/apps-light.png), [dark](pulse-hub-windows/apps-dark.png) |
| chat | yes | picture | picture | symbols 15, Button style | [light](pulse-hub-windows/chat-light.png), [dark](pulse-hub-windows/chat-dark.png) |
| permissions | yes | picture | picture | symbols 14, dark divider | [light](pulse-hub-windows/permissions-light.png), [dark](pulse-hub-windows/permissions-dark.png) |
| accounts | yes | picture | picture | symbols 17, dark divider | [light](pulse-hub-windows/accounts-light.png), [dark](pulse-hub-windows/accounts-dark.png) |
| appearance | yes | picture | picture | symbols 21, run mismatch 1, cache bound (459) | [light](pulse-hub-windows/appearance-light.png), [dark](pulse-hub-windows/appearance-dark.png) |
| notifications | yes | picture | picture | symbols 15, dark divider | [light](pulse-hub-windows/notifications-light.png), [dark](pulse-hub-windows/notifications-dark.png) |
| general | yes | picture | picture | symbols 16, 22 oversize shapes skipped, cache bound (910) | [light](pulse-hub-windows/general-light.png), [dark](pulse-hub-windows/general-dark.png) |

What the pictures show against the Mac (Overview, the others alike; read the triptychs rather than this list):
- No icons anywhere (R1). The sidebar rows, card headers and status rows have empty gaps where the symbols are.
- Text sizes come from the body family at the requested size, so header text such as "Performance", "Network & swap" and the wordmark "PULSE" (Tanker fallback) truncate ("Performa...", "PU...") and the Memory column of the Performance card stacks its digits vertically. The Mac shows them whole.
- Card, banner and bar geometry, palette, section order, grouping ("Settings" heading), the two Review/Update buttons, the charts (bars drawn as rectangles) and the dark scheme come through and look recognisably the same layout.
- Opaque-black hit areas (R12) were suppressed in the host; they are why this is not a clean unpatched capture.
- Not verified at all: clicking, focus, typing in `TextField`, `Toggle`, `Menu`, scrolling, `.task` refresh, window resize, animations, accessibility tree, DPI other than 2.5. `preparedView` supplied the data; the live `.task` path was never run.

## 4. Effort

### Measured throughput (git timestamps, `docs/sr1-status.md`)

| Round | Scope | Start | End | Wall | Per block |
|---|---|---|---|---|---|
| 4 (hub-driven) | blocks 21-25, 41 cases at N=20, one lane beside the closure lane | 14 Oct 23:41 (hub track `5cc7e5206`; gap check `455bb09f3` 23:57) | 15 Oct 05:22 (`c19cec89a`; last N=20 run folder `20261015-050940`) | 5.4 h (23:57 to 05:22) | **1.08 h** (7.6 cases per hour) |
| 3, to first evidence | blocks 11-20 plus the F1-F3 tooling, 4 lanes | 13 Oct 21:18 (`716dd21b6`) | 14 Oct 03:06 (`2d42ddb2d`) | 5.8 h wall, 23.2 lane-hours | 0.58 h wall, **2.3 lane-hours** |
| 3, to delivered | same blocks, after the consolidation re-run (`b57416a2c`, 14 Oct 18:31) and the TextField text-origin fix (`d07df2581`, 19:54) | 21:18 | 19:54 next day | 22.6 h wall | **2.26 h wall** |

Includes authoring, runtime work, N=20 Windows and Mac runs, tests and status rows. Excludes Oracle review: round 4 is "delivered-pending-review", so no review time is measured. Round 3 contains one-off tooling (the manual clock, the interaction job, the semantic comparator), which makes its rate pessimistic for plain modifier blocks; round 4 contains no such tooling but no consolidation or review either, which makes it optimistic.

### Gaps grouped into blocks (a block = one case family at N=20 on a Mac pair)

| # | Block | Closes | Why one block |
|---|---|---|---|
| 1 | AnyView, single-child builder identity, `View.id` | G01, G11, G16 | type erasure and identity share the graph's expansion code (the probe needed both to render at all) |
| 2 | Accessibility modifiers | G02-G06 | one semantic-tree gate (UIA vs Mac AX dump, exists since F3) |
| 3 | Color alpha | G09, G10, R12 | transparent fills; includes diagnosing why alpha-0 paints black |
| 4 | `Text(verbatim:)`, `State(initialValue:)`, `ViewModifier`, `Scene`/`WindowGroup` | G07, G08, G18, G19 | API shapes with no pixels of their own |
| 5 | Font weights and width | G13, G14 | needs per-weight metrics |
| 6 | Baseline alignment | G12 | layout against Mac baselines |
| 7 | `layoutPriority` | G15 | layout algorithm |
| 8 | Multi-line `TextField(axis:)` | G17 | text input blocks were the slowest of round 3 |
| 9 | System fonts and text styles | R2, R3, R4 | measurement policy plus the truncation search |
| 10 | `lineLimit(n)` wrapping and run-geometry matching | R2 (n>1), R5 | |
| 11 | SF Symbol table for 38 symbols | R1 | the Mac layout metrics per symbol come from `factory/tools/symbol-metrics`; block 2 did four sizes of one symbol |
| 12 | Non-resizable symbol paint (font-sized symbols) | R1 | the painter only paints `resizable().scaledToFit()` |
| 13 | Large-radius and zero-size continuous shapes | R7, R8 | Apple's large-radius control points were never observed (comment in `ContinuousRoundedGeometry.swift`) |
| 14 | Dark `Divider` | R10 | |
| 15 | Button opacity, foreground style, empty frame | R11 | |
| 16 | Hub display font | R2 (Tanker) | **blocked by the licence**, not by effort; counted for the fallback only: a bundled system-equivalent face |

Not counted as blocks (engineering inside existing code, each under one block): R3 recursion, R6 identifier length, R9 cache bound, R8 work limit; G20 `RelativeDateTimeFormatter` is a Pulse-side `#if os(Windows)`.

### Arithmetic

- Blocks: 16 (a different split gives 13 to 19).
- Round-4 rate: 16 x 1.08 h = **17.3 h**, single lane, no review. This is the headline.
- Round-3 end-to-end rate: 16 x 2.26 h = **36.2 h** (4 lanes already in that rate).
- Lane view of the same: 16 x 2.3 lane-hours = 36.8 lane-hours (round 3), 17.3 lane-hours (round 4). With four lanes the block count divides, but blocks 9-12 share the text and symbol paint path and cannot run in parallel without merge conflicts (round 3 needed repair commits for exactly that: `639c20247`, `75a1d85c7`), so a four-lane critical path is not 17.3 / 4.
- Plus, not measured and not in either figure: Oracle review of 16 blocks; a hub-level fit pass after the blocks land (the Overview already shows truncation and stacking that more blocks will not by themselves fix); live behaviour (TextField, Toggle, Menu, `.task`, scroll); the Windows exe, engine attach and Rust staticlib.

### Uncertainty

The two measured rates differ by 2.1x. The block count is a judgement from 20 compile gaps and 12 render gaps; the compile gaps are cheap (single modifiers), the render gaps (symbols, fonts, shapes) are the expensive ones and are most like blocks 2, 25 and 1, which were the slow families. Round 4 shows what a modifier-sized block costs (0.5 to 1.5 h); no measured block resembles "all 38 symbols" or "all system fonts" and those two are where the figure is least reliable.

## 5. Reproduce

```
probes/pulse-hub/fetch-pulse.sh <new empty dir>                  # Pulse code at bd6bd3df
probes/pulse-hub/assemble.sh <that dir> <new empty dest>         # probe package, B1 applied
# Dell: stage with factory/tools/stage-product.py, copy the three product dirs, then
#   restage.sh (runtime-patch/ProbePatch.swift + patch_host.py P1-P14), run.ps1 / iter.ps1 (compile), buildhost.ps1 (FactoryProbe),
#   deploy.sh, setframe.sh 0, render.py (Sandbox interact job, 24 runs), status.py, compare.py, gaps.py
```

Paths and work dirs are those of this run (`D:\Claude\swiftright\.work\pulse-hub-20261015b`); the scripts take them as arguments or use that name. Probe-only changes, none in the product tree: shim stubs, `ProbePatch.swift`, `patch_host.py` (P1-P14), host-side P9 filter and a vectored exception handler, bypass B1.
