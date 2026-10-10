# SR1 plan: the parity factory and the full shell

Status: plan rev 3 (10 October 2026), incorporating Adrian's accepted validation findings and execution boundaries. Rev 1 (73533ef) was adversarially reviewed by Astra (gpt-6-astra, high);
dispositions are at the end. The plan itself is not implemented, but SR1 head-start work exists: ABI 0.6 (`4df7e67`), runtime inventory controls 62/62 (`14106d6`), Windows gallery build (`47e9066`), Mac oracle fixtures G1-G8 (`c9347a0`, sweep interrupted).

## Entry criteria (checked mechanically, not asserted)
Phase 0 specifications and independent capture/host spikes may start while SR0 is OPEN (Adrian, 10 October 2026).
Until closure, create new files only under `factory/`; do not edit runtime, renderer, bridge, `qualification/`, or
`probes/sr0-*`, which the Swift Mac session owns. Existing assets may be inspected, but work that depends on a frozen
contract or ABI waits until `docs/sr0-status.md` says CLOSED with every SR0 row PASS and receipts bound to the frozen SR0 tuple
(bridge ABI 0.6, renderer `E280F4A9…`; the pinned final tuple is tuple 08 in `docs/sr0-snapshot.md` section 2d and `qualification/tuple-final.json`, but desktop receipts were since re-run on tuple 09, staged in `docs/sr0-tuple09-staging.md` (FreshOnBridge `8650BBFC…`, same renderer); read the current tuple and status from `docs/sr0-status.md` and `docs/sr0-snapshot.md`, not from this line), and slice contract v1.0 and the bridge interface are
frozen. Tuple 09 is the intended closure tuple, not an accepted baseline until that closure is recorded.
SR0's results are bounded slice evidence for the SR0 inventory only; SR1 must not assume anything outside it.

## What already exists (reuse, do not rebuild)
Verified present in the repository on 10 October 2026. SR0 is still OPEN (`docs/sr0-status.md:7`); these are probe-grade assets, so reuse them and harden them under the factory's own specs rather than rewriting them.

**Start here.** Start Phase 0 and independent spikes with minimal scaffolding before implementing components or expanding foundations. Read in order: `docs/architecture.md`, `docs/sr0-findings.md` (lessons, gaps, decisions), then this plan. SR0's final tuple and per-stage status live in `docs/sr0-status.md` and `docs/sr0-snapshot.md`; check them for the current tuple before binding any receipt.

- Recorders and assembler (Mac and Windows): `probes/sr0-o/f1-cross/` has `Sources/F1MacRecord`, `Sources/F1Assemble`, `uia-recorder/` (Windows UIA), `scripts/` (record-mac, run-cross, schedule-cross, pull-win, win-cross), recordings in `cross/` (F1-F9 plus F3 variants and F6-reduced), and the results in `CROSS-ALL.md`.
- Comparator: `probes/sr0-o/comparator/Sources/TraceKit` (`Comparator.swift`, `Normalizer.swift`, `Repeatability.swift`, `Schema.swift`) and `TraceTool`. Allowances are scoped to fixture, step, leaf and node; the schema carries test conditions including motion, and a condition mismatch fails.
- Runner, fault controls and tuple pinning: `qualification/run.py` (declared stage order with closure gate; injected-fault traces per config and per allowance), `qualification/tuple-final.json`, `qualification/test_run.py`.
- Canonicalizer: `probes/sr0-o/fixtures/scripts/normalize-hash.py` (with `test_normalize_hash.py`), including the unordered-completion rule for the F6 A/B pair (`f6_unordered_completions`, marked "proposed" contract C9). Repeat harness: `repeat20.sh`, `sr1-repeat20.sh`, `sr1-summary.py`, `run-self-test.sh`.
- Clean-machine harnesses: `qualification/clean-machine/windows/` (Windows Sandbox: `run-sandbox.ps1`, `sandbox-background.ps1`, `run-w08-recovery.ps1` for MSIX interrupted-update recovery, `with-desktop-lock.ps1`) and macOS `mac-clean-run.sh`, `mac-vm-offline.sh`, `mac-clean-checklist.md` (Tart VM); `receipt.schema.json`.
- Pixel assertions and capture: `examples/BridgeSmoke` (`Sources/BridgePixels`, `scripts/drive-pixels.ps1`, `schedule-pixels.ps1`; results `result-bridgepixels09.txt`).
- Text geometry, modal and cold-open probes: `examples/BridgeGeoModal` (`Sources/TextGeom06`, `Modal06`, `ColdOpen06`; `result-*09.txt`).
- Workload, analyzer and Mac workload: `probes/sr0-b/workload` (`WorkloadCore`, `WorkloadWin`, `WorkloadMac`, `SckRecorder`, `analysis/analyze_workload.py`); Mac result `probes/sr0-b/workload/results/MAC-WORKLOAD.md`.
- Runtime features added since rev 2: `onChange`, initial focus and motion start on first tick in `probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime` (`FocusTraversal.swift`, `Animation.swift`, `Graph.swift`); `ButtonFocusGate` in `packages/SwiftRightBridge/Sources/SwiftRightBridge/ButtonFocusGate.swift`.

**Decisions to carry (Adrian, 10 October 2026 unless noted):**
- Windows OS animation setting is not mapped to reduce motion; traces record the motion condition instead.
- Performance bar is no worse than Mac SwiftUI on the same workload; missed vblanks are reported, not gated (`docs/sr0-findings.md` section 11).
- Never delete anything on the Dell over SSH (`docs/sr0-findings.md:290`).
- Window-targeted input is the default; keep ordinary test windows in the background. Before any Dell windowed run,
  hold `D:\Claude\desktop.lock` (`with-desktop-lock.ps1`). Native-only IME and Narrator tests need an interactive
  session, a foreground check and abort-on-focus-loss; existing `drive-ime.ps1` and `drive-narrator.ps1` already
  implement those guards. Spike a second isolated interactive Dell session; until it is qualified, native-only
  tests use the shared desktop under the same lock, with foreground limited to that test interval.

**Lessons that change the factory design:**
- An allowance is scoped to fixture, step, leaf and node, with a reason; anything broader is rejected.
- Traces must carry their test conditions (for example motion) and a mismatch fails the comparison.
- Recorder normalisations can hide product defects, so every normalisation needs its own injected-fault control.
- Three runs per side is below the contract's 20; a verdict from fewer is not evidence.
- A self-test that never ran a path (the animated path) passes vacuously; require a positive observation per path.

**Starting point per component:**
- F1 Catalogue: new.
- F2 Block registry: new.
- F3 Cases: new; axes follow the F1-F9 configs in `probes/sr0-o/f1-cross/cross/configs.json`.
- F4 Probes: starts from the frozen same-source fixtures in `probes/sr0-c/same-source` and `probes/sr0-o/fixtures`.
- F5 Mac capture: `F1MacRecord`, the Tart VM harness, `SckRecorder`, and the `normalize-hash.py` canonicalizer.
- F6 Headless replay: `probes/sr0-s/fresh-runtime` (runtime without renderer; its Tests).
- F7 Windows replay: `uia-recorder`, `examples/BridgeSmoke`, `examples/BridgeGeoModal`, Windows Sandbox and desktop-lock scripts.
- F8 Comparator: `probes/sr0-o/comparator/TraceKit`.
- F9 Report: new; `CROSS-ALL.md` and the `qualification/run.py` stage output are the prototypes.
- F10 Trusted gate: `qualification/run.py` closure gate, `tuple-final.json` and `test_run.py`.
- F11 Queue: new.
- F12 Shell journeys and demand map: new.

## Goal
Rebuild the full desktop shell that ships today as Tauri + React (RightKit `app-shell`, `settings-ui`,
`onboarding`, `platform-ui`, `theme`, `media-ui`, `pdf-ui`, `legal-ui`, and each app's own React screens) as one
SwiftUI codebase: real SwiftUI on macOS, SwiftRight on Windows, with machine-verified parity. Open source; AI agents
and community contributors take work from one queue. The factory is the system that turns "SwiftUI behaviour on
Mac" into "verified equivalent on Windows", and keeps it verified.

## Principles carried from the architecture
- AD5: parity is a tested contract with macOS as oracle; every API in the inventory is `inventory`, `adapted` or
  `unsupported` (unsupported fails Windows compilation; nothing is a silent no-op).
- AD7: automation does labour, not judgement. Acceptance criteria (recipes, tolerances, masks, channel obligations,
  comparator code, normalisers and golden promotion) are maintainer-owned and change only through review;
  implementations cannot change them. Every normalisation needs its own injected-fault control.
- AD8: no transpiler. Swift compiles as Swift on both platforms.

## Overview
```
SDK ─F1─> catalogue ─F2─> block registry ─┐
                                           ├─> recipes (authored, reviewed) ─F3─> cases ─F4─> probes
shell journeys (F12) ─> demand map ───────┘
probes ─┬─F5─> Mac capture (VM) ─> candidates ─> reviewed goldens ──┐
        ├─F6─> headless replay (unit evidence) ───────────┼─F8─> verdicts ─F9─> report
        └─F7─> Windows native replay (Dell) ──────────────┘          │
                       F10 trusted gate <─────────────────────────────┘ ─> status: parity
                       F11 queue (tickets for blocks whose dependencies are at parity)
```

## Phase 0: specifications before code
The factory is built against written, executable specifications. Phase 0 delivers, in `factory/spec/`:
1. JSON Schemas (versioned, with migration rules) for: catalogue, block registry, recipe, kind/capability
   obligations, case, capture outputs (layout, ax, events, anim, image manifest, text runs, meta), verdict, receipt,
   ticket, waiver.
2. Canonicalisation and hashing: canonical JSON (sorted keys, fixed float formatting, explicit encoding of infinity
   and NaN), content hashes for every artifact, and the tuple definition (SDK, macOS build, toolchains, runtime commit,
   renderer hash, host hashes, factory version, acceptance-config hash). Any tuple change invalidates affected verdicts.
3. The probe-host protocol: how a host loads a case, applies environment, drives stimuli, waits for settlement
   (quiescence rules and timeouts), reports outputs, resets between cases, and correlates clocks (a monotonic stimulus
   clock shared by stimulus, transaction and frame records).
4. Identity mapping: probe tags to view identity on Mac (geometry/AX) and on Windows (runtime node / AccessKit id).
5. Input drivers per platform (window-targeted by default; native-only interactive tests use foreground checks and
   abort-on-focus-loss), with the stimulus vocabulary of contract §4 extended only after that contract is frozen.
6. Normalisation tables: Mac AX role/action ↔ Windows UIA control type/pattern; units (point ↔ DIP ↔ physical pixel)
   at each scale.
7. CLI behaviour: exit codes, idempotence, caching by input hash, partial-failure and resume semantics.
8. Host operations: Mac VM provisioning (display, login session, scale, colour profile, capture permission), Dell
   host locking (one desktop lane), recovery after a crashed run, and artifact storage (retrieval, retention,
   community read access).
9. Queue rules: ticket ownership and expiry, conflict handling, waiver authority (maintainers only).
10. One worked end-to-end example (`Rectangle` with `.fill` and `.frame`) through every stage, with all files checked
   in, used as the factory's own regression fixture.

## Components

**F1. Catalogue.** `swift-symbolgraph-extract` for `SwiftUI` and `SwiftUICore` with pinned compiler, target, SDK and
flags; extension graphs merged; re-exports reconciled; output canonicalised. Completeness is audited against the
`.swiftinterface` files (every public declaration there must appear, or be listed as hidden with its attribute),
because documentation-visibility attributes can hide public symbols from graphs. Keyed by USR so SDK upgrades diff.

**F2. Block registry.** Symbols grouped into blocks (a view and its initialisers; a modifier family; a protocol and
its defaults; a property wrapper). Each block declares: symbols, status (`inventory` / `adapted` / `unsupported`
plus progress `not-started | recipe | implementing | blocked | parity | waived`), and **semantic dependencies** curated by
maintainers (environment, preferences, transactions, identity), not inferred only from signatures. Dependency cycles
(e.g. `Layout` ↔ stacks) are resolved by declared bootstrap groups that reach parity together.

**Recipes (authored, reviewed).** Signatures cannot describe behaviour, so every block has a recipe: concrete witness
types (a real `Layout`, a real `PreferenceKey`, model types with identities), resource fixtures (images, fonts),
legal compositions, stimuli, expected state changes and assertions, plus negative cases (misuse that must not compile,
or must behave as Apple does). Recipes are written by agents or contributors and **accepted only by maintainer
review**. F3 generates mechanical variations from a recipe; the recipe is the specification.

**Obligations per capability.** Channels are assigned by what a block can affect, not by one exclusive kind:
layout, paint, hit-testing, accessibility (provider and external), focus, text, events/state, animation,
presentation (windows, popovers, menus). A modifier like `.disabled` carries hit-testing, accessibility and paint
obligations; an environment value carries the obligations of every view it influences in its recipe. Every case
also has a compile obligation (positive and negative) and AD5 inventory status.

**F3. Cases.** Expanded from the recipe over its axes (proposals, parameters, environment: appearance, Dynamic Type,
layout direction, reduced motion, scale). Pairwise reduction for broad axes, plus recipe-declared full products for
interacting axes (e.g. width × priority × text), plus stateful composition sequences (insert/remove/reorder under
animation and environment change). Each case has a stable ID; the expected-case set per block is fixed by the recipe,
so a missing case is a failure, not a skip.

**F4. Probes.** Generated same-source Swift (frozen conditional import block). Instrumentation must be transparent:
each recipe includes an instrumentation-transparency check (the block with and without probes produces the same
layout and paint).

**F5. Mac capture (oracle).** Runs inside the clean macOS VM, never on the user's screen. Capture classes, each
qualified against window screenshots before use:
- layout: frames of **tagged observable boundaries** via geometry hooks, plus proposal/measurement records from
  witness `Layout` containers, baselines and alignment guides; not "every view" (internal control trees and
  unmaterialised lazy children are not observable and are not claimed);
- text: `Text` runs, lines and glyph-run bounds via `TextRenderer` where available; text editors observed through
  their native text APIs; fonts, fallback and colour recorded;
- paint: offscreen `NSHostingView` capture for in-window content where qualified; real windows plus ScreenCaptureKit
  for compositor-dependent effects, popovers, menus and sheets (VM provisioned with capture permission and fixed
  scale/colour);
- accessibility: in-process provider snapshot **and** external AX client checks per control/presentation family;
- animation: stimulus and transaction times on the shared clock, per-frame interpolated values from samplers, and
  actual presented frames (screen capture timestamps) recorded separately; dropped frames kept as evidence;
- events/state: SR0 TraceKit schema.
**Repeatability:** every case runs 20 independent times per platform (SR0 contract rule). Semantic assertions and
required event orderings agree exactly after reviewed normalisation, including declared unordered sets. Timing is a
separate comparison: retain raw stimulus, transaction, sampler and presented-frame timestamps; compare durations,
interruption velocity and stalls against recipe-declared bounds. Relative-order normalisation applies only to the
semantic projection and never replaces timing evidence. A required case with semantic disagreement, missing evidence
or a failed timing bound is `blocked` and blocks parity; it is never silently excluded.
**Candidate baselines:** retain accepted traces, assertions and environment metadata. New OS/toolchain observations
create candidate baselines, compared against accepted expectations before adoption (`docs/architecture.md` §11).
Automation cannot bless drift by regenerating expected output. Initial acceptance and subsequent promotion require
maintainer review, preserve previous goldens and record the candidate, diff, tuple and review identity. Normalisers
are protected acceptance configuration; each rule must reject its own injected-fault control before use.

**F6. Headless replay (unit evidence only).** The runtime without renderer, on any OS. Valid for state, identity,
event order and layout arithmetic **when text measurement is replayed from recorded native measurements**; the
runtime's default fixed-advance measurer is not native. Headless results never grant parity; they give fast feedback.

**F7. Windows native replay.** The real renderer on the Windows host, producing the same capture classes:
offscreen readback for in-window paint, real windows plus screen capture for compositor and presentation cases,
AccessKit provider snapshots plus external UI Automation checks, presented-frame timing (PresentMon), text runs from
the runtime's text pipeline. Window-targeted input is the default. Native-only IME and Narrator tests use an isolated
interactive session once qualified; until then, use the shared Dell desktop under `D:\Claude\desktop.lock`, with
foreground checks and abort-on-focus-loss. Every windowed run holds that lock; ordinary test windows stay background.

**F8. Comparator.** Per channel, with explicit units (physical pixels at the capture scale, converted from points):
- layout: edge tolerance stated per edge class (hairlines and hit boundaries 0 px; content edges ≤ 1 px at 2x);
- paint: region metrics on declared regions (not only global SSIM), with mask provenance recorded; text regions are
  never simply masked: their runs, baselines, colour and ink coverage are compared from the text channel;
- hit-testing, paint and accessibility bounds checked for mutual consistency on each platform;
- animation: exact semantic completion/order assertions, separately from bounded timing comparisons on the shared
  clock for durations, interpolation error, interruption velocity, presented-frame cadence and stalls; raw timing
  evidence is retained. Timing comparison is new F8 work: the existing TraceKit comparator ignores timestamps;
- accessibility: provider tree and external client results through the versioned normalisation tables.
**Calibration:** every channel is calibrated with deliberately broken renders and behaviours (mutation fixtures:
missing glyph, 1 px shift, wrong colour, ignored `.disabled`, wrong curve). A channel is usable only when it rejects
its mutation set and accepts repeated correct runs.

**F9. Report.** Per block: cases side by side (Mac | Windows | diff) with channel numbers; dashboard by status,
capability and shell demand. Local; published only when asked.

**F10. Trusted gate.** Runs in a trusted environment from the merged commit, never from contributor-provided results:
rebuilds runtime and renderer, validates the complete case manifest against the recipe, runs the block's cases plus
**randomised extra cases generated with a seed chosen by the gate at run time** (variations the contributor could not
tune against). Every generated seed gets its own matching Mac capture, 20-run semantic repeatability qualification,
bounded timing comparison and 20-run Windows replay; archive both sides, case inputs and seed. Missing or unstable
Mac evidence blocks that seeded comparison, never falls back to another case's golden. Newly captured references
remain candidates; recording a random run cannot promote or replace accepted goldens. The gate runs comparator and
per-normalisation fault controls, and the regression set: all blocks that depend on the changed code;
any change to core runtime, layout, text or renderer runs the full parity suite. Acceptance configuration (recipes,
tolerances, masks, obligations, comparator, normalisers and golden promotion) is protected: changes need maintainer review and re-run every affected
verdict. Receipts record tuple, inputs, seeds and results and are verifiable by re-running.

**F11. Queue.** Tickets for blocks whose dependencies are at parity (or in the same bootstrap group): recipe, cases,
failing verdicts, report link. Ownership, expiry and conflict rules from Phase 0.

**F12. Shell journeys and demand map.** Before choosing blocks: inventory the shell's user journeys (navigation,
settings, onboarding, media, PDF, legal, shortcuts, tray, dialogs, persistence, updates, recovery) and map each to the
blocks and service adapters it needs. Shell screens are written in SwiftUI on Mac first; their Windows compile errors
give the block backlog; journeys (not only screens) are the acceptance tests. Service adapters, engine integration,
reliability and performance remain under the architecture's later gates (SR2–SR4); screen parity alone is not
shell acceptance.

## Foundations (renderer and bridge)
Run capture and host spikes first with minimal scaffolding. Add bridge and renderer foundations only as needed by
each pilot round, after SR0 closure, through the normal ABI revision and requalification:
vector paths (fill/stroke, caps, joins, dashes, trim), full affine transforms (today translation only), right-to-left
layout and text (today unsupported), images beyond rev 0.6 (scaling modes, symbols), clipping by shape, scrolling and
hit-testing, offscreen readback and a semantic export for the capture hosts, popovers/menus/sheets as real windows.

## Pilot
Spikes first, then cumulative rounds (each round adds to the previous):
- Spikes (one each, prove or kill a capture method): text runs via `TextRenderer` vs Windows text pipeline; a
  `Layout` witness capturing proposals; ScreenCaptureKit in the VM for a popover; animation presented-frame timing on
  both platforms; external AX/UIA for one control; mutation calibration for each channel; feasibility of a second
  isolated interactive session on the Dell without disrupting its shared desktop. While SR0 is OPEN, spikes stay
  under `factory/` and use independent scaffolding; frozen-contract/ABI-dependent integration is held.
- Round 1 (5 blocks): `Rectangle`/`RoundedRectangle` + `.fill`/`.stroke`, `Image`, `ZStack` + `.overlay`,
  `Text` (bundled font), one custom `Layout`.
- Round 2 (+10, 15 total): `ScrollView`, `Toggle`, `.disabled`, `.padding`/`.frame`, `PreferenceKey`, `.popover`,
  `withAnimation` spring with interruption, `TextField` with IME, environment (`.font`, colour scheme), `.contextMenu`.
- Round 3 (+20, 35 total): the first shell journey's remaining blocks.
Exit of each round: every case passes on the frozen tuple **and** every channel still rejects its mutation set; the
factory changes needed in the round are recorded. The queue opens when round 3 completes with no factory change and
the gate catches every seeded mutation.

## Estimates
None until the spikes run. The spikes measure capture and comparator throughput, recipe authoring time, build and
native-host time per case, and mutation detection rate; estimates for rounds and for the shell are derived from those
numbers.

## Pass criteria
- Factory: a block goes from recipe to `parity` through the trusted gate, with manual work limited to authoring the
  recipe and implementation, acceptance review and reviewed golden promotion; every channel and normalisation
  passes its mutation calibration.
- Shell: every shell journey passes on Windows x64 on the frozen tuple, plus the SR2–SR4 gates for services,
  reliability and performance.
- Every claim is a committed recipe, golden and receipt.

## Open decisions
- Recipe authoring rate and reviewer capacity (measured in the spikes).
- Which SDK version the goldens pin (ceiling = pinned Xcode SDK).
- arm64 Windows (deferred; needs hardware).

## Review dispositions (Astra, rev 1)
| # | Finding | Disposition |
|---|---|---|
| 1 | Interfaces unspecified | Accepted: Phase 0 specification deliverables. Blocks mass production, not the start of factory work (the specs are the first factory work). |
| 2 | Signatures cannot generate behaviour | Accepted: authored, reviewed recipes; generation varies recipes. |
| 3 | Unstable exclusion = false parity | Accepted: 20-run normalised agreement; unstable required cases block parity. |
| 4 | Comparator gameable | Accepted with change: protected acceptance config, trusted rebuild, mutation tests, full regression. Instead of secret holdouts (awkward for open source), the gate generates seeded random cases at run time. |
| 5 | SR0 success asserted early | Accepted: mechanical entry criteria; SR0 results are bounded slice evidence. |
| 6 | Per-kind channels too narrow | Accepted: obligations per capability; AD5 statuses restored. |
| 7 | Text measurement source | Accepted: text channel (runs, baselines, colour, ink) via `TextRenderer` and the Windows text pipeline; no plain masking. |
| 8 | Geometry hooks ≠ every view | Accepted: tagged observable boundaries, `Layout` witnesses, transparency checks. |
| 9 | `cacheDisplay` not universal | Accepted: capture classes qualified; real windows + ScreenCaptureKit for compositor/presentation. |
| 10 | In-process AX insufficient | Accepted: provider snapshots plus external AX/UIA per family. |
| 11 | Animation sampling ≠ presentation | Accepted: shared clock, interpolation and presented frames recorded separately. |
| 12 | Headless uses fake metrics | Accepted: headless is unit evidence; native measurements replayed; never grants parity. |
| 13 | Pairwise / signature deps miss composition | Accepted: curated semantic deps, bootstrap groups, declared full products, stateful sequences, full regression on core changes. |
| 14 | Tolerances lack power | Accepted: unit conversions, edge-class tolerances, region metrics, mutation calibration. |
| 15 | Symbol graphs not exhaustive | Accepted: pinned extraction, merged graphs, audit against `.swiftinterface`. |
| 16 | VM and ABI foundations understated | Accepted: VM provisioning in Phase 0; foundations list expanded (paths, affine, RTL, readback, semantic export). |
| 17 | Screens ≠ shell acceptance | Accepted: journeys as acceptance; SR2–SR4 gates preserved. |
| 18 | Pilot/estimates favour easy coverage | Accepted: spikes first, hard blocks in rounds 1–2, cumulative counts, mutation-detection exit, estimates only from measured spikes. |

## Review dispositions (rev 3, accepted by Adrian, 10 October 2026)
| Finding | Applied change |
|---|---|
| Background-only input conflicts with native tests | Targeted default; native-only interactive lane with foreground checks and abort; spike isolated Dell session, shared locked desktop until qualified. |
| Timing normalisation can hide animation defects | Exact semantic agreement separated from bounded timing comparison; retain raw evidence; new F8 work. |
| Golden promotion unspecified | Candidate/accepted baseline lifecycle, reviewed promotion, protected normalisers and one fault control per rule. |
| Random cases lack matching oracles | Each seed gets Mac capture, repeatability qualification and Windows replay; archive both sides. |
| Foundations precede feasibility | Minimal-scaffolding spikes first, foundations per pilot round after SR0 closure. |
| Registry state and workload reference | Added `blocked`; corrected Mac workload result path. |
| Start while SR0 remains OPEN | Phase 0 and independent spikes authorised under `factory/`; frozen-contract/ABI-dependent work waits for recorded closure. |
