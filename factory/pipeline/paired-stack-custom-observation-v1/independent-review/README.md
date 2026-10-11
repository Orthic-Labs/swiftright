# Paired stack/custom observation independent review

Offline independent review of producer stage `47cc44505c72e5feaa96250c83cbb37bc60d42e0d2e7f79707741b308146fe62`.

Review re-hashes all 881 raw Windows/Mac files, verifies exact case/source joins & twenty-run Mac summaries, preserves stack renderer failure as `probe-failure` with no native DIFF, & records custom packet as `observed-partial` from one PrintWindow repeat pair, one screen repeat pair & root UIA with zero children.

Semantic layout, shape, provider & timing stay unavailable; goldens remain zero, parity unavailable, qualification held, candidate-only.

Run offline:

```text
python3 generate_review.py
python3 test_review.py
```
