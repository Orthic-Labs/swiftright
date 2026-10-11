# Paired disabled observation, version 1

This packet compares one corrected Windows native observation with 20 existing Mac runs for `swiftui.disabled.recipe/case/f113195a59446fc4`. It is observational only: parity is held, no registry or baseline promotion is made, and zero Windows batches meet qualification.

The adapter accepts only the frozen input manifest and exact listed file bytes. It binds the generated Swift source to the F9 case, checks each raw Windows/Mac observation and emits a separate observational report. `evidence/observational-report.json` retains all 78 raw evidence paths, byte sizes and SHA-256 values. The generated report and `evidence/OBSERVATION.md` are reproducible with:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/pipeline/paired-disabled-observation-v1 python3 factory/pipeline/paired-disabled-observation-v1/generate.py
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/pipeline/paired-disabled-observation-v1 python3 -m unittest discover -s factory/pipeline/paired-disabled-observation-v1 -p 'test_*.py' -v
```

Observed semantics: Windows UIA reports `Continue` enabled; Mac raw AX reports matching label and `AXPress`, but exposes no enabled field. F9 hit-testing remains untested because no input/invoke or callback receipt exists. Windows ABI metrics were 800×1396 while corrected owned client area was 800×600 at 240 DPI. Continue text measured 160.27344 px, snapped to 160 px, height 60 px, one line. Mac layout frame was 79×24; its resolved font is held and its text-renderer channel is empty. Raw paint is not cross-provider semantic normalization.

Twenty repeated Mac captures, including identical screenshot hashes, do not establish controlled background occlusion. Mac offscreen begin/end intervals are same-process render intervals only. Windows compile duration is separate; qualified timing is unavailable. No geometry or pixel parity is asserted.

`versioned-snapshots/` retains pre-fix adapter/test bytes. `evidence/input-manifest.json` pins source, case, plans, observations, 20 Mac runs and Windows sidecars. `evidence/stage-manifest.json` and `evidence/SHA256SUMS` pin this packet; the stage manifest excludes itself and the checksum file to avoid circular hashes.
