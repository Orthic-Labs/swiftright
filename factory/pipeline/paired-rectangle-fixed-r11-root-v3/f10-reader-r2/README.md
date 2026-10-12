# F10 Rectangle typed Windows reader r2

This folder records observed F10 Rectangle evidence from materializer r5 & reader r2. Existing byte archives remain under ignored `.factory-work/f10-rectangle-typed-r5/windows-archives`; `reader-input.json` points there explicitly. No binary archive was relocated or recreated.

## Observed result

- Materializer: 20 typed Windows captures, 20/20 materialized; 73 archived files per capture, 25 native files, 13 host bindings, 21 runtime files.
- Materializer peak: 32 MiB.
- Production reader/gate: 20/20 admitted; 10/10 fault cases blocked.
- Reader peak: 58 MiB.
- Status remains `typed-observational-only`, `qualified=false`, `nativeParityGranted=false`, `held-observation-only`, `semantic=held`, `timing=raw-only`.
- Rectangle RGB mismatch remains preserved in observed evidence; no normalization or parity promotion is applied.

## Preserved evidence

- `typed-captures.json`: copied from `.factory-work/f10-rectangle-typed-r5/typed-captures.json`.
- `materializer-receipt.json`: copied from `.factory-work/f10-rectangle-typed-r5/materializer-receipt.json`.
- `reader-controls-r2.json`: copied from `.factory-work/f10-rectangle-typed-r5/reader-controls-r2.json`.
- `reader-input.json`: same input map with archive paths made explicit relative to this folder: `../../../../.factory-work/f10-rectangle-typed-r5/windows-archives`.

## Source pins

- Materializer `materialize_typed_windows_r1.py`: `bd9f5b535be0a544ad69d93ee935e3028f4236ce96d6c665f084ecb9f9c6bc0f`.
- Reader controls `run_reader_controls_r1.py`: `212252280dd529ebd6b95ef552e8df753b7d5f026c1df16b29104c4ad31159ae`.
- Windows admission gate `factory/gate/windows_exit_admission.py`: `ed40e781ed03d34bc15fbf5cb41d76a8b890982b9a708886129c1f35e78f4d72`.
- Compile-request regression `factory/tests/test_windows_compile_request.py`: `bf35a6804620ddca5e750ffd66a8ae79f6391faa748e532da77af22bab058154`.

Gate accepts legacy exact compiler request & optional exact integer `maxParallelJobs=1`, requiring measured `--jobs 1`; wrong types/values, missing/undeclared flag, & unknown fields remain blocked.
