# Text paired exit-proof reader r1

Source-only diagnostic adapter for exact Mac exit-proof20 & Windows Text20. It consumes fresh Mac exit-proof raw JSON/AX/PNG/stream/event bytes plus new `exit-proof.json` receipts. Historical Mac root supplies case/tuple/compiler/source provenance only; old run observations and old PIDs never enter rows. It never opens or attaches to recorded PIDs; fresh PID joins are receipt-to-raw-file checks only. Every fresh Mac run requires host/plain/instrumented/external-AX exit0, `waitPidObserved`, sealed streams, no timeout/kill/RSS/output cap, four distinct receipt PIDs, verified stdout/stderr/events refs, & plain/instrumented PNG bytes/hash. Twenty runs therefore require 80 verified child receipts. PNGs must be 890 bytes with measured hash `sha256:31783bae3552b53af3573cd9cd4b15666c71f91ed4374d04e5a51eb0b6461f23`.

AX selection is explicit `value == "Aa"`; title-only nodes are ignored, while multiple Aa witnesses hold. Raw AX screen origins, raw Windows UIA bounds, DPI conversion, source/tuple/case/compiler joins, & stream/image hashes remain preserved. Output is always diagnostic with `qualification: false`; semantic, paint, wrapping, timing, & parity claims remain held where fields are absent or differ. Height comparison retains Mac 28 DIP vs Windows 28.8 DIP.

Root command:

```sh
python3 factory/pipeline/pilot-next-source-v1/paired-text-exit-proof-root-v1/compare_text_exit_proof.py \
  --mac-capture-root factory/oracle/mac/text-origin-r11-root-v1/observed-paint-mac20-r1 \
  --mac-exit-root factory/oracle/mac/text-origin-r11-root-v1/exit-proof-replay-v1/observed-mac-exit-count20-r1 \
  --count1-graph factory/native/windows/pilot-text-paint-root-v2/capture-count1-r12-root-v7-sources \
  --count20-graph factory/native/windows/pilot-text-paint-root-v2/capture-count20-r10-root-v3-sources \
  --windows-root factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1 \
  --output .factory-work/paired-text-exit-proof-r1/report.json
```

Controls use same production predicates & explicit roots:

```sh
python3 factory/pipeline/pilot-next-source-v1/paired-text-exit-proof-root-v1/test_text_exit_proof_controls.py \
  --mac-capture-root factory/oracle/mac/text-origin-r11-root-v1/observed-paint-mac20-r1 \
  --mac-exit-root factory/oracle/mac/text-origin-r11-root-v1/exit-proof-replay-v1/observed-mac-exit-count20-r1
```

Inputs are bounded: individual files 16 MiB, JSON 4 MiB, aggregate reads 128 MiB, 256 source rows. Raw evidence stays at original paths. No qualification, golden, or parity promotion is emitted.
