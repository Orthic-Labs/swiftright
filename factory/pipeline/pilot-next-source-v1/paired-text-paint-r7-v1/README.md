# Text paint paired20 adapter r7

`compare_text_paint.py` is source-only, bounded, raw-observation adapter. It
reads explicit Mac20 evidence from
`factory/oracle/mac/text-origin-r11-root-v1/observed-paint-mac20-r1` & an
explicit future Windows20 root. It never edits either root, invents terminal
proof, or promotes parity.

Mac identity is fixed by capture evidence: case
`swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418`,
case hash
`sha256:29807aa918aa7c2c1c4a4705eb324b0020f29060be7359d4923694aeb5d437ad`,
tuple `sr1-text-paint-v2-r11-paired20-20261012`, renderer
`sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`,
Windows host
`sha256:33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7`.

Windows producer uses actual `control/coordinator.json` & `control/task-result.json`:
both must report integer `count: 20`, completed source-bound status,
`wholeBatchExitConfirmed`, `lockReleased`, zero-error `taskParentProof`, & a
passed memory receipt with `activeProcessCount: 1`, 1GiB, flags 512, and
`killOnJobClose: false`. Adapter derives 20 only after explicit
`native/native-01` through `native/native-20` each pass original exit,
terminal-worker, sealed-stream, renderer/worker raw-file checks. It never
creates `successfulCount` or `jobActiveCount: 0`. Existing Count1 root is held
because coordinator/task-result count is 1.

Run after Windows20 archive exists:

```text
python3 factory/pipeline/pilot-next-source-v1/paired-text-paint-r7-v1/compare_text_paint.py \
  --mac-root factory/oracle/mac/text-origin-r11-root-v1/observed-paint-mac20-r1 \
  --windows-root <explicit-windows20-root> \
  --output .factory-work/text-paint-r7/paired-report.json
```

Exit `2` means held input or identity evidence. Output remains raw-only with
`status: observed-diagnostic`, `parity: held`, `semantic: held`, and
`timing: raw-only`; no qualification or golden claim is emitted. JSON/file
reads are bounded by 4MiB per JSON, 16MiB per raw file, & 128MiB aggregate.

`test_text_paint_controls.py` calls same production validator against bounded
fault fixtures. Root should run controls only after source review & before
using any future Windows20 receipt.
