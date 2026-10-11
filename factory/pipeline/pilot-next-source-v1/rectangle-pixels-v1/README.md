# Rectangle pixel pair comparator

`compare_rectangle_pixels.py` consumes one fresh input manifest containing exactly 20 Mac compositor PNG refs & 20 Windows PrintWindow PNG refs. `source` must carry exact `sourceHash`, `tupleID`/`tupleHash`, `caseID`/`caseHash`, `recipeID`/`recipeHash`, runtime/renderer values, & hash/byte refs for tuple, case, recipe, & witness source. Every image row carries repository-relative `image.path`, measured `bytes`, `sha256`, run index, all source joins, `observedScale`, `viewportPx`, `viewportDip`, `framePx`, `placement`, `clip`, & `rawEvidence.geometryRef`/`pixelsRef` derived JSON refs plus `rawRefs` to original native geometry/pixel JSON. Derived values must equal authored row metadata; original refs remain hash-bound inputs. Reader stats files before opening, rejects symlink/traversal paths, streams 1 MiB hashes, caps each image at 8 MiB/4 MP, & preserves raw archives.

Expected contract records Rectangle `system.red` semantic fill at 40×20 DIP while preserving measured platform RGB & geometry. Mac contract records compositor 40×52 pixels with content frame `(0,32,40,20)` & rounded bottom-corner clipping; Windows contract records PrintWindow 800×600 pixels / 320×240 DIP viewport with red content at client top-leading origin `(0,0)`, 100×50 observed pixels at scale 2.5. Each row carries measured dominant RGBA; reader joins raw geometry/pixel JSON values, reports raw red bbox, RGB, scale, frame, viewport DIP, placement, clipping, evidence refs, per-platform repeatability, & ordered 20-run identity. Pair report compares shape DIP, viewport DIP, placement, & clipping while keeping host differences visible; it performs no centering or cross-platform geometry normalization. Semantic label provenance (`expected.fillSemantic`) stays separate from exact RGB equality, so platform color differences remain visible. Canonical tuple/case/recipe hashes & case.recipe/case.tuple joins are checked with factory canonical JSON. AX/provider semantics remain held; no shape inference or native action occurs.

Root runs after both 20-image archives are hash-pinned:

```sh
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/rectangle-pixels-v1/compare_rectangle_pixels.py \
  --manifest factory/pipeline/pilot-next-source-v1/rectangle-pixels-v1/inputs/rectangle-pixels-r1.json \
  --repo-root /Volumes/D/claude/swiftright \
  --output .factory-work/rectangle-pixels-r1/comparison.json
```

Mutation controls use same baseline & must reject frame, viewport, color, placement, clipping, raw-evidence, source-join, & image-hash faults with `nativeActions: 0`:

```sh
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/rectangle-pixels-v1/test_rectangle_pixels_controls.py \
  --manifest factory/pipeline/pilot-next-source-v1/rectangle-pixels-v1/inputs/rectangle-pixels-r1.json \
  --repo-root /Volumes/D/claude/swiftright \
  --output .factory-work/rectangle-pixels-r1/controls.json
```

Result is diagnostic only & does not qualify AX, provider exports, tuple, or parity.
