# Fresh Padding Windows capture packet r2

Source-only successor for fresh Padding Count1 then Count20. It binds fresh generated case, manifest, tuple, recipe, witness, runtime tree, exact compiler receipt, executable, renderer, serializer, candidate binding, & source plan. Historical seeded case `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258` is rejected. Count1 proof must be fresh before Count20 admission.

Measured plan is `windows-padding-fresh-compile-plan-v1`; it carries no embedded tuple. Tuple identity stays external through `tupleRef`/`tupleHash`; capture/dispatch joins must use source-input tuple identity. Receipt may expose `freshPlanSha256` instead of legacy `planSha256`.

Known current inputs: case `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9`; case raw SHA `f9a8e685f55c8063fde159bfb58926c637cd740fc8c6edb71de702933b7e3878`; tuple `sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011`; Windows host `3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a`; runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`; renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`.

On Mac, use `prepare-padding-inputs.py` once with explicit local metadata & a Windows remap map. It derives `capture-plan.json`, integration bindings, helper manifest, & helper hashes from historical `factory/native/windows/padding-capture-lease-capture-v1`; it never resolves Windows paths locally:

```sh
python3 prepare-padding-inputs.py \
  --donor-root factory/native/windows/padding-capture-lease-capture-v1 \
  --case-meta <fresh-case.json> --tuple-meta <fresh-tuple.json> \
  --plan-meta <fresh-plan.json> --compile-meta <compile-receipt.json> \
  --windows-input-map <windows-input-map.json> \
  --count 1 --output <source-inputs-v3.json>
```

`windows-input-map.json` must contain `{"inputs":{"role":{"path":"D:\\\\...","sha256":"sha256:<64hex>","bytes":N}}}`. Paths, hashes, & byte counts are copied as Windows-only refs; they are never asserted from Mac filesystem paths. Output is `factory-padding-source-inputs-v3`, status `fresh-source-bound-windows-remap-required`, & retains `nativeActions:0`/`lockActions:0`. Historical donor context is explicitly marked historical, so it cannot qualify fresh capture.

On Windows, consume this v3 remap metadata with stage installer after root has supplied each exact Windows file. For source ZIP, pass `--root <common-root>` to `pack-padding-sources.py`; ZIP entries preserve each full relative path under `sources/`, with 64MiB/file, 128MiB total, 128-file, regular-file, duplicate, & changed-file guards. Never pass basename-only files.

For legacy all-local Windows preparation, `prepare-padding-inputs.py` retains v2 CLI. Run `test-padding-source-controls.py` before install. Install into fresh `.factory-work` paths with `install-padding-sources.ps1`; installer copies only hash-bound explicit rows, writes `stage-manifest.json`, & performs no compiler/native/lock action.

Count1 admission uses `controller-padding-count1.ps1` source identity checks. Root passes `compiledHostPackagePath` as exact fresh compiler package directory; producer package must equal this pinned path. Root then invokes reviewed PaddingCapture-v3 Count1 producer with fresh package/exe/renderer & captures original handle, UIA, PrintWindow/background pixels, bounded stdout/stderr, 1GiB job (`0x200`), no kill-on-close, 15s close/5s drain, & exact owner CAS. Count1 receipt must state `factory-padding-count1-proof-v1`, completed source-bound observation, kernel exit 0, sealed streams, active count 0, peak <=1GiB, & lock released. Count20 controller requires this proof, then `issue-padding-metadata-v1.ps1` emits 20 ordered fresh IDs. `interactive-task-padding-repeat.ps1` admits self-job 1GiB/0x200 before dispatch; Count20 uses same bounded UIA+PrintWindow worker and exact original-handle cleanup.

Root-only commands after source staging:

```powershell
powershell.exe -NoProfile -NonInteractive -File .\test-padding-source-controls.ps1 ...
powershell.exe -NoProfile -NonInteractive -File .\controller-padding-count1.ps1 -Config <count1-config.json> -PreflightOnly
powershell.exe -NoProfile -NonInteractive -File .\controller-padding-count20.ps1 -Config <count20-config.json> -PreflightOnly
```

No qualification, parity, or golden claim is emitted by this packet. Native actions remain root-owned.

Measured compile closure now available from `factory/pipeline/padding-fresh-case-v1/windows-incremental-root-v4/root-controls-r2/actual-final-r2/`: plan `root-controls-r1/plan-incremental-v4.json` SHA `214e73d4239604be7580add966c86fd387fa7985fef79ee307de81846a8b2433`; executable SHA `3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a`, 3,721,216 bytes; receipt/raw streams are exact explicit inputs. Runtime source tree had 21 rows/248,686 bytes & source had 13 rows/45,590 bytes. Receipt records kernel wait 0, exit 0, active count 0, sealed/drained streams, measured `--jobs 1`, & null frontend-thread override.

Use `-ProducerRoot <stage>\producer`, `-IntegrationGuardPath <stage>\integration-fresh-padding-v1.ps1`, & `-IntegrationGuardHash <sha256>` when invoking either dispatch. Count1 dispatch takes `-Count 1`, fresh issued metadata, & no Count1 proof input. Count20 dispatch takes `-Count 20` plus `-Count1ProofPath` & `-Count1ProofHash`; it refuses any missing or mismatched Count1 proof. `make-padding-config.ps1` emits exact `count1-config.json` or `count20-config.json` with fresh output/run roots, 1GiB, flags 512, no-kill, 15s close, 5s drain, & native/lock counters zero.
