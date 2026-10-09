# SR1 plan: the parity factory and the full shell

Status: plan, 9 October 2026. Starts when SR0 closes (bridge ABI 0.6 and slice contract v1.0 frozen).

## Goal

Rebuild the full desktop shell that today ships as Tauri + React (RightKit `app-shell`, `settings-ui`,
`onboarding`, `platform-ui`, `theme`, `media-ui`, `pdf-ui`, `legal-ui`, plus each app's own React screens)
as one SwiftUI codebase that runs as real SwiftUI on macOS and through SwiftRight on Windows, with
machine-verified parity. Open source; community contributors and AI agents take work from the same queue.

SR0 proved the approach (same source, runtime semantics, renderer speed, accessibility, IME, packaging).
SR1 builds the system that turns "SwiftUI block on Mac" into "verified equivalent on Windows" at scale.
The first 20 blocks prove that system, not feasibility.

## The system

### 1. Catalogue (what exists)
- Extract every public SwiftUI and SwiftUICore declaration from the pinned SDK's `.swiftinterface`
  (Xcode 27: SwiftUI interface 34,178 lines) into `catalogue/swiftui.json`: symbol, kind, full signature,
  availability, generic constraints.
- Group into blocks: a view, a modifier family, a protocol (Shape, Layout, Animatable), a property wrapper.
- Each block gets a status: `not-started | spec | implementing | parity | waived(reason)`.

### 2. Demand map (what the shell needs)
- Inventory the React shell: every component and behaviour in the RightKit UI packages and each app's screens.
- Map each to the SwiftUI blocks it needs (e.g. sidebar navigation → `NavigationSplitView`, `List(selection:)`,
  `.searchable`; settings → `Form`, `Toggle`, `Picker`, `Slider`, `TextField`).
- Write the shell's screens in SwiftUI on Mac first (real SwiftUI, works today). That source is the acceptance
  test for Windows, and its compile errors on Windows are the exact block backlog.
- Priority = blocks the shell needs, ordered by dependency; everything else in the catalogue follows.

### 3. Golden capture on Mac (what Apple does)
For each block a generated probe runs the block across an input matrix (sizes / proposals, parameter values,
states, environment: dark mode, Dynamic Type, reduced motion, RTL). Runs on real SwiftUI inside the clean
macOS VM (Tart, headless; never on the user's screen). Captured per case:
- Layout: every view's frame (geometry hooks), exact numbers.
- Pixels: offscreen render of a hosting view at 1x and 2x (see F5; `ImageRenderer` cannot draw AppKit-backed controls).
- Animation: an `Animatable` probe logs the interpolated value every frame for each curve
  (default, spring, easeInOut, interrupted, reduced motion) -> curve samples with timestamps.
- Semantics: accessibility tree (role, label, value, actions) and event trace (state, lifecycle, focus),
  as SR0's recorder and comparator already do.
Outputs are committed goldens under `goldens/<block>/<case>/`. Goldens are the written parity spec.

### 4. Windows replay
The identical probe source compiles against SwiftRight, renders offscreen through the renderer on the Windows
host (needs an offscreen render target in the renderer, an SR1 foundation item), and emits the same four outputs.

### 5. Comparison and report
- Layout and accessibility: exact within 0.5 pt.
- Pixels: perceptual diff (SSIM) above a per-block threshold; text-heavy cases compare layout + glyph boxes
  instead of raw pixels, because the two OS rasterizers differ.
- Animation: curve error within tolerance at each sample.
- One generated HTML page per block: Mac | Windows | diff, with numbers. Aggregated dashboard by status.
- A block reaches `parity` only when every case passes on the frozen tuple.

### 6. Work queue (agents and community)
A ticket = one block + its spec (signature, cases, goldens) + the failing comparison. An agent (Codex or
community) implements it in the runtime (Swift) and, when needed, the renderer (Rust) until the comparison
passes. Merge gate = comparator green + no regression in the existing goldens. No result is trusted without it.

### 7. App acceptance
The SwiftUI shell screens compile unchanged on Windows and every screen is compared side by side, same as a block.
Existing Swift apps (dictation pill, Pulse notch with its CI view renders) are early acceptance targets.

## What is deterministic

The factory is scripts, not agents: catalogue extraction, probe generation (from each block's signature plus a
standard input matrix per block kind, with per-block overrides), Mac golden capture, Windows replay, comparison and
reports. Agents (Codex or community) are used only to implement each block's Windows behaviour until its comparison
passes, and occasionally to tune a block's input matrix.

## Factory implementation guide

### What the factory is
A repository directory plus one command-line tool, `factory`, that turns a SwiftUI symbol into a verified Windows
equivalent through fixed, reproducible stages. Every stage reads files and writes files; nothing depends on a chat,
an agent's memory or a person's judgement except the implementation step. Every output names the inputs it came
from by content hash, so any result can be reproduced or invalidated mechanically.

```
catalogue ──> blocks ──> cases ──> probes ──┬──> Mac capture (VM) ──────> goldens ─┐
 (SDK)        (registry)  (matrix)  (Swift)  ├──> headless replay (any OS) ────────┼──> compare ──> verdicts ──> report
                                             └──> Windows render replay (Dell) ────┘                 │
                                                                                     gate <──────────┘ (merge decision)
```

### Repository layout
```
factory/
  tool/                      # `factory` CLI (Swift package; Python only for image/report helpers)
  catalogue/                 # generated: swiftui.symbols.json, swiftuicore.symbols.json, blocks.json
  blocks/<block-id>/         # one directory per block
    block.yaml               # registry entry (hand-editable overrides live here)
    cases.json               # generated case matrix
    probe/Probe.swift        # generated same-source probe
  goldens/<sdk>/<block-id>/<case-id>/      # Mac outputs (JSON in git; images by hash, see Storage)
  runs/<tuple>/<block-id>/<case-id>/       # Windows / headless outputs (not committed; receipts are)
  verdicts/<tuple>/<block-id>.json         # committed comparison receipts
  report/                    # generated HTML
  kinds/                     # case-matrix templates per block kind
  host/                      # probe hosts: MacHost (SwiftUI), HeadlessHost (runtime only), WinHost (runtime + renderer)
```

### Components

**F1. Catalogue extractor** (`factory catalogue`). Runs `swift-symbolgraph-extract` (ships with Xcode) for the
`SwiftUI` and `SwiftUICore` modules against the pinned SDK, giving Apple's exact public symbol graph as JSON:
every declaration, signature, generic constraints, availability, protocol conformances and member relationships.
No hand parsing of `.swiftinterface`. Output is keyed by Apple's stable symbol identifier (USR) so a later SDK can
be diffed against it. Deterministic: same SDK, byte-identical output.

**F2. Block registry** (`factory blocks`). Groups symbols into blocks using rules over the symbol graph: one view
type and its initialisers; one modifier family (all overloads of `.padding`); one protocol and its defaults
(`Shape`, `Layout`, `Animatable`); one property wrapper. Writes `blocks/<id>/block.yaml`:
- `id`, `symbols` (USRs), `kind` (see Kinds), `depends_on` (blocks whose behaviour it needs, derived from the
  signatures plus overrides), `case_template`, `tolerances`, `status`, `waivers` (each with reason and owner).
- Overrides are hand-edited keys in the same file and survive regeneration.

**F3. Case matrix generator** (`factory plan <block>`). Expands the block's kind template (`kinds/<kind>.yaml`) into
`cases.json`. A case = one concrete configuration with a stable ID (hash of its parameters). Axes:
- proposals: `nil`, `0×0`, small, natural, large, unbounded, one fixed axis;
- parameters: each initialiser/modifier argument over representative values (enums fully, numbers at edges);
- environment: light/dark, Dynamic Type sizes, layout direction LTR/RTL, reduced motion, scale 1x/2x;
- composition: the block alone, inside a stack, inside a fixed frame, nested in itself where legal;
- interaction scripts (controls only): tap, focus, type, drag, keyboard, with the expected state changes.
Pairwise (all-pairs) reduction keeps the count bounded; a block may opt into the full product for critical axes.

**F4. Probe generator** (`factory generate <block>`). Writes `Probe.swift`: one same-source file using the frozen
conditional import block (`SwiftUI` + `SwiftRightUI` on Mac, `SwiftRightUI` on Windows). For each case it emits a
`ProbeCase { id, environment, body, script }` and wraps the body in the factory instrumentation:
- `.probeID(_:)` on every node of interest, recording frames in the probe's root coordinate space (Mac:
  `onGeometryChange`; SwiftRight: the runtime's layout result, same schema);
- an `AnimationSampler` (an `Animatable` view whose `animatableData` setter logs value + timestamp each frame);
- event hooks reusing SR0's TraceKit schema (state, lifecycle, focus, task) so existing comparator code applies.
Probe code is generated, never hand-written, so a probe bug is fixed once in the generator.

**F5. Mac capture** (`factory capture-mac`). Builds `MacHost` with the generated probes and runs it inside the clean
macOS VM (Tart, headless display; never on the user's screen). Per case it writes:
- `layout.json`: frames of every `probeID` node;
- `image@1x.png`, `image@2x.png`: rendered from an offscreen `NSHostingView` with
  `bitmapImageRepForCachingDisplay` / `cacheDisplay` (works for AppKit-backed controls, unlike `ImageRenderer`,
  which draws controls such as `TextField`, `List` and `ScrollView` as placeholders);
- `ax.json`: the accessibility tree walked in-process (the app reads its own tree; no permission grant needed);
- `events.jsonl`: TraceKit events for scripted cases;
- `anim.json`: sampler curves, from a window on the VM display so the real display link drives animation;
- `meta.json`: macOS build, SDK version, probe source hash, host hash.
Determinism checks: each case runs 3 times; any difference between runs marks the case `unstable` and it is
excluded from gating until its template is fixed (SR0 used the same repeatability rule).

**F6. Headless replay** (`factory replay-headless`). Runs the same probes against the SwiftRight runtime with no
renderer, on any OS, including the Mac. Produces `layout.json`, `events.jsonl`, `anim.json` and the runtime's own
semantic tree. Most parity failures (layout, state, animation timing) show up here in seconds, without the Dell.

**F7. Windows render replay** (`factory replay-windows`). On the Windows host, `WinHost` runs the probes through the
runtime and the real renderer and produces the same files as F5. Requires one new bridge function, an offscreen
render of a window to an RGBA buffer, versioned through the normal ABI process. `ax.json` comes from the renderer's
AccessKit tree; a sampled subset of cases is also checked through real UI Automation so the AccessKit-to-UIA step
stays covered. Runs as one-shot interactive scheduled tasks, window-targeted input only, as in SR0.

**F8. Comparator** (`factory compare`). Extends SR0's TraceKit. One verdict per case with numbers:
- layout: frames equal within 0.5 pt after normalising to the probe root;
- semantics: accessibility trees equal after a fixed Mac→Windows role and action mapping table (versioned);
- events: SR0's trace comparison (order, identity, state);
- animation: both curves resampled to a common timebase; max value error and duration error within tolerance;
- pixels: per-tile SSIM above the block's threshold, with text regions masked and compared through glyph boxes
  from the layout output instead (the two OSes rasterise text differently; exact text pixels are never a goal).
A case fails if any applicable channel fails; channels that do not apply to a block kind are recorded as `n/a`.

**F9. Report** (`factory report`). Static HTML: per block, each case as Mac | Windows | diff image with the channel
numbers; a dashboard of block statuses by kind and by shell demand. Local file; published only when asked.

**F10. Gate** (`factory gate <block>`). The merge decision for a ticket: rebuild runtime (and renderer if touched),
headless replay + Windows replay for the block and for a fixed regression set (all `parity` blocks it depends on
and that depend on it), compare, write a signed receipt to `verdicts/`. Green gate = block moves to `parity`.

**F11. Queue** (`factory tickets`). For each non-parity block whose `depends_on` are all `parity`: emits a ticket
(block id, symbols with Apple's signatures, case list, failing verdicts, report link, files likely to change).
Tickets are plain files (later GitHub issues when the repository is public). Any agent or contributor takes one,
implements, runs `factory gate`, opens a change with the receipt.

### Kinds (and what parity means for each)
| Kind | Examples | Channels compared |
|---|---|---|
| shape | `Rectangle`, `Circle`, `Capsule`, `Path`, `trim`, `stroke` | layout, pixels |
| leaf view | `Text`, `Image`, `Label`, `Divider` | layout, semantics, pixels (text by glyph boxes) |
| container / layout | `HStack`, `ZStack`, `Grid`, `ScrollView`, `Layout` | layout, semantics, events (scroll), pixels |
| modifier | `.padding`, `.frame`, `.overlay`, `.clipShape`, `.opacity` | layout, pixels |
| control | `Button`, `Toggle`, `Slider`, `Picker`, `TextField` | layout, semantics, events (scripted), pixels |
| animation | `withAnimation`, `.animation`, springs, transitions | animation curves, final layout |
| state / environment | `@State`, `@Environment`, `@FocusState` | events |
| presentation | `.sheet`, `.popover`, `.contextMenu`, `NavigationSplitView` | layout, semantics, events |

### Text and fonts
System fonts differ between macOS and Windows, so text can never match pixel for pixel. Probes therefore use a
bundled open font for metric-exact layout cases, and a second set uses each OS's system font, compared only for
semantics and relative layout (wrapping, truncation, baseline alignment). The rules are part of the `leaf view` kind.

### Storage
JSON goldens, verdicts and receipts are committed. Images are stored by content hash outside Git (private object
store per workspace rules); the JSON records the hash, so a missing or altered image is detected.

### Running it
```
factory catalogue                 # once per SDK
factory blocks && factory plan --all
factory generate <block>
factory capture-mac <block>       # Tart VM
factory replay-headless <block>   # anywhere
factory replay-windows <block>    # Dell
factory compare <block> && factory report
factory gate <block>              # merge decision
factory tickets                   # next work
```

### What the pilot proves
5, then 10, then 20 blocks through every stage above, chosen to exercise each component: shapes (renderer paths),
`Image`, `ZStack` + `.overlay`, `ScrollView` (events), one control with a script (`Toggle`), one animation.
The pilot passes when the 20-block round needs no factory change.

## Order

1. Foundations the factory needs: catalogue extractor, golden capture harness (Mac VM), Windows offscreen
   replay, comparator + report, renderer support for paths/shapes, images, clipping, scrolling, hit-testing.
2. Pilot ramp: 5 blocks through the whole pipeline -> fix the factory -> 10 more -> fix -> 20 more; when 20 pass with
   no factory fixes, open the queue. Fix the factory, not the blocks, when it struggles.
3. Shell demand map + shell screens written in SwiftUI on Mac.
4. Scale: open the queue to parallel agents, shell-needed blocks first, by dependency layer.
5. Shell parity on Windows; then the rest of the catalogue for community/open source.

## Estimates (agentic critical path, unmeasured)

Factory build including renderer paths/images/offscreen target: about 12 h. Then 5 blocks about 2 h, 10 about 3 h,
20 about 4 h, each followed by factory fixes.

## Pass criteria
- Factory: a new block goes from ticket to `parity` with no manual steps besides the implementation.
- Shell: every shell screen passes side-by-side comparison on the frozen tuple on Windows x64.
- Every claim is a committed golden + comparison result.

## Open decisions
- Text comparison method (glyph boxes vs pixels) per case class.
- Which SDK version the goldens pin (ceiling = pinned Xcode SDK).
- arm64 Windows (deferred; needs hardware).
