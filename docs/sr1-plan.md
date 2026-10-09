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
- Pixels: offscreen render via `ImageRenderer` at 1x and 2x.
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
