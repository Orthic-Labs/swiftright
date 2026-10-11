# Corrected seed source lineage v2

Append-only supplement for `factory/oracle/mac/seed-corrections-v1`; v1 remains unchanged.

Per each of five seed cases, packet archives exact surviving `Witness.swift`, adapted `CaptureHost.swift`, build stdout/stderr & joins to v1 binary, summary source/adapter/binary hashes & all 20 instrumented raw hashes.

`policy/source-policy.json` pins capture source & compiler argv template:

`/usr/bin/xcrun swiftc -parse-as-library -O -o <capture-host> <Witness.swift> <CaptureHost.swift>`

Original producer did not emit actual OS compiler argv, PID, timestamps or return-code receipt. Fields stay explicitly missing; no process receipt is reconstructed.

```sh
python3 verify.py .
```
