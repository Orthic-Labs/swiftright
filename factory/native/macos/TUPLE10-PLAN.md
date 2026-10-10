Tuple10 native capture preparation

Capture starts only after pipeline issues final bound tuple10 bundle & `docs/sr0-status.md` explicitly records SR0 CLOSED for tuple10. Candidate/unbound bundles cannot execute this plan. Runtime commit bound by new factory tuple is independently recorded from SR0 staged runtime `8e47`; renderer/ABI profile remains governed by closure receipt.

Pipeline supplies canonical primary/seed case directories, ordered manifests, actual manifest/source/recipe/case hashes, tuple/runtime commit, acceptance config hash & closure proof. Validate current files against supplied hashes before native execution. Old 471 captures & their tuple/source bindings remain historical bytes; no rebinding.

1. Fresh first-five primaries: shapes, image, stack-overlay, text, custom-layout; 20 independent processes per case/mode. Report first-five current roots & receipts immediately.
2. Fresh next-five primaries: scroll-view, toggle, disabled, padding-frame, preference-key; 20 per case/mode.
3. Pipeline-owned independent frozen seed10 plan: fresh 20 per case. Never reuse baseline capture bytes or primary evidence as seeded runs.
4. Verify canonical captures/raw/image hashes & independent PID evidence; bind new evidence selection explicitly by case hash/source hash/tuple hash.

Fresh work paths & execution stay beneath `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1`; each batch uses new owned scratch subtree. Fresh output roots identify tuple10/config/seed. Existing recorder unchanged; fresh read-only AX client checks exact owned PID/path/hash/window title. No permission requests; any failed no-prompt grant holds only relevant channel. No broad process termination.

Channel scope: actual offscreen paint, root Layout proposals/placements, TextRenderer metrics, owned-window compositor, actual NSHostingView fitting size/bounds/backing scale, bounded external witness AX. ScrollView offscreen blank stays held unless new actual evidence disproves it; compositor plus actual witness AX/root host geometry remain separate observations. Shape/custom witness AX absence, internal Layout callbacks & TextRenderer glyph-font identity stay held. Process-only font registration may establish native resource/provider identity, independently from glyph-font identity.

Preparation qualification: independent ScrollView adapter control in `evidence/20261011-host-metrics-control` records actual NSHostingView128×80 fitting size from owned native window using no-prompt grants. Tuple10 case capture awaits final bound pipeline bundle.

Dependency audit

`CaptureHost.swift` + fixed `FactoryHostQualification` source → independent qualification binary → postclosure host-measurement JSON/hash → tuple.hostHashes → canonical cases → F4 generated manifests/sources → per-case capture binaries/provenance. Qualification source embeds no tuple, case hash, acceptance config or runtime commit. Receipt records actual runtime commit as factory context; macOS binary links SwiftUI/AppKit rather than SwiftRight runtime. Per-case source/binary hashes never feed tuple.hostHashes. Receipt archives adapter template/source & compiled adapter beneath its own internal work subtree, so later repository edits cannot change bound measurement bytes.

Postclosure commands

Root supplies actual values for `FACTORY_RUNTIME_COMMIT` & `TUPLE10_CLOSURE_RECEIPT` after explicit closure. Run host measurement then; it precedes final tuple binding. Capture commands require canonical case roots & exact source-bound manifest variables from final bound bundle. Pending candidate profile cannot authorize case captures. Use fresh output/scratch paths for every dispatch.

```sh
python3 -m factory.native.macos.measure_host \
  --runtime-commit "$FACTORY_RUNTIME_COMMIT" \
  --closure-receipt "$TUPLE10_CLOSURE_RECEIPT" \
  --scratch /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/tuple10-postclosure-host \
  --output factory/native/macos/evidence/tuple10-postclosure-host
```

Pipeline validates resulting `host-measurement.json` source/adapter/binary hashes & raw receipt hash, then binds final tuple/config/cases. After receiving bound bundle:

```sh
python3 -m factory.native.macos.capture \
  --manifest "$TUPLE10_MAC_PRIMARY_SHAPES" \
  --manifest "$TUPLE10_MAC_PRIMARY_IMAGE" \
  --manifest "$TUPLE10_MAC_PRIMARY_STACK" \
  --manifest "$TUPLE10_MAC_PRIMARY_TEXT" \
  --manifest "$TUPLE10_MAC_PRIMARY_LAYOUT" \
  --case-root "$TUPLE10_PRIMARY_CASE_ROOT" \
  --scratch /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/tuple10-primary-first-five \
  --output factory/native/macos/evidence/tuple10-primary-first-five --runs 20
python3 -m factory.native.macos.check_evidence factory/native/macos/evidence/tuple10-primary-first-five

python3 -m factory.native.macos.capture \
  --manifest "$TUPLE10_MAC_PRIMARY_SCROLL" \
  --manifest "$TUPLE10_MAC_PRIMARY_TOGGLE" \
  --manifest "$TUPLE10_MAC_PRIMARY_DISABLED" \
  --manifest "$TUPLE10_MAC_PRIMARY_PADDING" \
  --manifest "$TUPLE10_MAC_PRIMARY_PREFERENCE" \
  --case-root "$TUPLE10_PRIMARY_CASE_ROOT" \
  --scratch /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/tuple10-primary-next-five \
  --output factory/native/macos/evidence/tuple10-primary-next-five --runs 20
python3 -m factory.native.macos.check_evidence factory/native/macos/evidence/tuple10-primary-next-five
```

Independent seeded dispatch repeats exact ten `--manifest` arguments supplied by frozen seed plan, uses its canonical seed case-root, fresh internal scratch `.../sr1/tuple10-own-seed` & fresh evidence `.../evidence/tuple10-own-seed`, with `--runs 20`. Bound seed ID/config/hash is written into dispatch receipt before execution. Verify resulting root using `check_evidence`; never substitute primary bytes.

`measure_host` checks explicit CLOSED tuple10 status, exact closure status hash/decision/time, full actual repository commit & separation from staged SR0 commit before building. No window capture occurs during measurement. Native inventory reads no-prompt AX/screen booleans, actual display geometry/backing scale & installed font families/system-font control. A denied grant is recorded; corresponding capture channel is held without permission request.

`rootHostGeometry` means actual NSHostingView `fittingSize`, frame/bounds & content-layout rectangle in points plus backing scale. It reports neither child positions nor internal Layout callbacks. Its source is hashed compositor raw output; it cannot promote blank ScrollView offscreen paint or absent witness AX.

```sh
python3 -m factory.native.macos.capture \
  --manifest "$TUPLE10_MAC_SEED_SHAPES" \
  --manifest "$TUPLE10_MAC_SEED_IMAGE" \
  --manifest "$TUPLE10_MAC_SEED_STACK" \
  --manifest "$TUPLE10_MAC_SEED_TEXT" \
  --manifest "$TUPLE10_MAC_SEED_LAYOUT" \
  --manifest "$TUPLE10_MAC_SEED_SCROLL" \
  --manifest "$TUPLE10_MAC_SEED_TOGGLE" \
  --manifest "$TUPLE10_MAC_SEED_DISABLED" \
  --manifest "$TUPLE10_MAC_SEED_PADDING" \
  --manifest "$TUPLE10_MAC_SEED_PREFERENCE" \
  --case-root "$TUPLE10_SEED_CASE_ROOT" \
  --scratch /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/tuple10-own-seed \
  --output factory/native/macos/evidence/tuple10-own-seed --runs 20
python3 -m factory.native.macos.check_evidence factory/native/macos/evidence/tuple10-own-seed
```
