# Independent enabled AX review

This packet replays producer pins offline: 196 input references, producer stage 191 files, no-prompt AX preflight, source/case/probe joins, fresh client build receipts, existing capture-host identity, & 20 new AX-only runs.

Each run joins owner PID/start, client PID, case/source/binary hashes, invocation exit/no-input fields, raw AX status, exact single `Continue` AXButton, & `AXEnabled` observed bool `true`. Run files contain no paint capture outputs. Prior 20-run summary & owner receipts remain separately pinned.

Result is observed AX-only evidence: no paint, geometry, native parity, hit-testing, promotion, or external binary-byte archive claim.

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/native/macos/disabled-enabled-observation-v1/independent-review python3 factory/native/macos/disabled-enabled-observation-v1/independent-review/generate_review.py
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/native/macos/disabled-enabled-observation-v1/independent-review python3 -m unittest discover -s factory/native/macos/disabled-enabled-observation-v1/independent-review -p 'test_*.py' -v
```
