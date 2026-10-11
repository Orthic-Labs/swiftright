# Independent Round2 recipe review

Offline review of frozen `factory/recipes/round2-extra-v1` source packet. Producer bytes remain untouched.

Review covers root stage hashes/sizes, five schema-valid recipes, five positive & five negative Swift source hashes, exact candidate-registry source joins, 19 projection records, 28 synthetic fault receipts, native hold fields, zero compiler/native runs, & F4 unsupported-block hold.

Run:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. factory/.venv/bin/python factory/recipes/round2-extra-v1/independent-review/review_r1.py
```

Result is source/schema/projection review only; no typecheck, native capture, tuple, registry promotion, or semantic dependency claim.
