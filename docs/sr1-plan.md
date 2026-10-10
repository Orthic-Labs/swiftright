# SR1 plan: the parity factory and the full shell

Status: plan rev 2, 9 October 2026. Rev 1 (73533ef) was adversarially reviewed by Astra (gpt-6-astra, high);
dispositions are at the end. The plan itself is not implemented, but SR1 head-start work exists: ABI 0.6 (`4df7e67`), runtime inventory controls 62/62 (`14106d6`), Windows gallery build (`47e9066`), Mac oracle fixtures G1-G8 (`c9347a0`, sweep interrupted).

## Entry criteria (checked mechanically, not asserted)
SR1 starts only when `docs/sr0-status.md` shows every SR0 row PASS with receipts bound to the frozen SR0 tuple
(bridge ABI 0.6, renderer `E280F4A9…`, fixture host `7673A2D5…`, tuple 08 per `docs/sr0-snapshot.md` section 2d), and slice contract v1.0 and the bridge interface are
frozen. SR0's results are bounded slice evidence for the SR0 inventory only; SR1 must not assume anything outside it.

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
  comparator code) are maintainer-owned and change only through review; implementations cannot change them.
- AD8: no transpiler. Swift compiles as Swift on both platforms.

## Overview
```
SDK ─F1─> catalogue ─F2─> block registry ─┐
                                           ├─> recipes (authored, reviewed) ─F3─> cases ─F4─> probes
shell journeys (F12) ─> demand map ───────┘
probes ─┬─F5─> Mac capture (VM) ─────────────> goldens ──┐
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
5. Input drivers per platform (window-targeted only), with the stimulus vocabulary of contract §4 extended.
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
plus progress `not-started | recipe | implementing | parity | waived`), and **semantic dependencies** curated by
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
**Repeatability:** every case runs 20 times (SR0 contract rule); outputs are normalised (timestamps to relative order,
declared unordered sets) before agreement is checked. A required case that does not agree across runs is `blocked`
and blocks the block's parity until its recipe or normalisation is fixed; it is never silently excluded.

**F6. Headless replay (unit evidence only).** The runtime without renderer, on any OS. Valid for state, identity,
event order and layout arithmetic **when text measurement is replayed from recorded native measurements**; the
runtime's default fixed-advance measurer is not native. Headless results never grant parity; they give fast feedback.

**F7. Windows native replay.** The real renderer on the Windows host, producing the same capture classes:
offscreen readback for in-window paint, real windows plus screen capture for compositor and presentation cases,
AccessKit provider snapshots plus external UI Automation checks, presented-frame timing (PresentMon), text runs from
the runtime's text pipeline. One desktop lane; window-targeted input only.

**F8. Comparator.** Per channel, with explicit units (physical pixels at the capture scale, converted from points):
- layout: edge tolerance stated per edge class (hairlines and hit boundaries 0 px; content edges ≤ 1 px at 2x);
- paint: region metrics on declared regions (not only global SSIM), with mask provenance recorded; text regions are
  never simply masked: their runs, baselines, colour and ink coverage are compared from the text channel;
- hit-testing, paint and accessibility bounds checked for mutual consistency on each platform;
- animation: timing from the shared clock, interpolation error bound, interruption velocity and completion semantics,
  presented-frame cadence and stalls;
- accessibility: provider tree and external client results through the versioned normalisation tables.
**Calibration:** every channel is calibrated with deliberately broken renders and behaviours (mutation fixtures:
missing glyph, 1 px shift, wrong colour, ignored `.disabled`, wrong curve). A channel is usable only when it rejects
its mutation set and accepts repeated correct runs.

**F9. Report.** Per block: cases side by side (Mac | Windows | diff) with channel numbers; dashboard by status,
capability and shell demand. Local; published only when asked.

**F10. Trusted gate.** Runs in a trusted environment from the merged commit, never from contributor-provided results:
rebuilds runtime and renderer, validates the complete case manifest against the recipe, runs the block's cases plus
**randomised extra cases generated with a seed chosen by the gate at run time** (variations the contributor could not
tune against), runs comparator mutation tests, and runs the regression set: all blocks that depend on the changed code;
any change to core runtime, layout, text or renderer runs the full parity suite. Acceptance configuration (recipes,
tolerances, masks, obligations, comparator) is protected: changes need maintainer review and re-run every affected
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
Before the pilot the bridge and renderer need, each through the normal ABI revision and requalification:
vector paths (fill/stroke, caps, joins, dashes, trim), full affine transforms (today translation only), right-to-left
layout and text (today unsupported), images beyond rev 0.6 (scaling modes, symbols), clipping by shape, scrolling and
hit-testing, offscreen readback and a semantic export for the capture hosts, popovers/menus/sheets as real windows.

## Pilot
Spikes first, then cumulative rounds (each round adds to the previous):
- Spikes (one each, prove or kill a capture method): text runs via `TextRenderer` vs Windows text pipeline; a
  `Layout` witness capturing proposals; ScreenCaptureKit in the VM for a popover; animation presented-frame timing on
  both platforms; external AX/UIA for one control; mutation calibration for each channel.
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
- Factory: a block goes from recipe to `parity` through the trusted gate with no manual step besides authoring the
  recipe and the implementation; every channel passes its mutation calibration.
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
