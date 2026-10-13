# Tuple12 R10 v6 source review

Source-only successors are pinned for root review. Frozen v5/co4 remain immutable.

- lifecycle v6: `qualification/tuple12-takeover/workload-controls-v6/`; run `a593d2dc2eacec6f43fd47c49ef278cc388ec98af9f644c49e02dc44a727765d`; task `c3c7bd8df105f8865fe83ba86fe67fe73b9306c2535e84cca9df9edb8b281e3e`; controls `1490ea2535b4404771507af36b8e614c2c6da9b2059c5d836e69d4f86c472bbb`.
- coordinator co5: `qualification/tuple12-takeover/workload-coordinator-v5/`; source `9ef569105c30226bad8410721423b06c44dc11fe2290437177dcd90c05f6714e`; controls `025ab27da127f3efea78136bc94066fd61630bb0b28621099fb6b9a602b65640`.
- matrix assembler v2: `qualification/assemble-tuple12-windows-full-v2.py`; source `d96c72527f77378f7b3f92f15d0dc14fdd3a833bef8fe380f5ced2fde79a803b`; controls `5f763bec1b2a13432f7a02248688860917cc7bcdeff4003a6eb801585ce8d1c6`; exact 16 configs × 20 runs = 320.

v6 records raw DWORD & signed exit for PM, workers, and samplers. PM cleanup stops exact owned ETW session, polls `logman query` until DataCollectorSetNotFound, and requires `session_absent=true` independently from PM process terminal proof. Semantic proof requires exactly three valid runs with guarded `--sr0-noactivate`, `HWND_BOTTOM`/`SWP_NOACTIVATE`, `WORKLOAD-WIN-DONE`, and `aborted=false`. Controls exercise signed-exit, session, semantic, and fault paths; both Python controls pass.

Current observed Workload r10-v4 packet remains failed/unadmitted: PM force-stop produced raw DWORD `4294967295` without signed/session proof; all runs recorded `background_noactivate=not-requested`. v6 addresses these source defects; root must parse/typecheck/build/run before admission.

Latest Full16 Count1 smoke v4 is failed & immutable at `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-full16-smoke-v4-r1`. Five cases passed before F3-vstack-1s failed: trace reports `renderer_window_revalidate=FAIL`, UIA root unavailable, then F1 focus timeout. No native assertions are relaxed; no 320-case qualification claim.
