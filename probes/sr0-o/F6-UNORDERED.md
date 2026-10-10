# F6 unordered completion pair (T11, CONTRACT C9 proposed)

Decision: the F6 `animation` A-complete/B-complete order is unordered; native SwiftUI swaps it ~4% (R6: 96 A-first / 4 B-first).

## Change
- `fixtures/scripts/normalize-hash.py`: `canonical_body` now shared; `f6_unordered_completions` keeps the two `complete` events (fixture F6, node `animation`, tag A/B) in their slots and sorts them by tag. Nothing else permutes. The canonical form id stays `sr0-a.canonical/v2`; accepted digests do not change.
- `conformance/sr0-slice/CONTRACT.md`: C9 text added after the §3 ordering rule.
- NOT done (owned elsewhere): `qualification/run.py canonical_body` must mirror the same function (it is documented as identical to normalize-hash.py). Until then the runner still reports the 2-variant F6 FAIL.

## Tests (`fixtures/scripts/test_normalize_hash.py`, `python3 -I test_normalize_hash.py`, 9 pass)
Swap passes. FAIL controls: B completes twice, B completes before B start, missing completion, reordered unrelated node events (and step relocation), start swap, wrong final state, other fixture id.

## Re-evaluation
- r6/f6 run1,13,23,24,25 (1 A-first, 4 B-first) and both candidate traces under conformance/candidates/F6: all equal accepted F6 digest 0a24aa9a3a7d.
- All 16 accepted `trace.jsonl` digests equal their manifest `canonical_sha256`.
- The 100-run set is committed only as `r6/f6/f6-100-events.jsonl` (receipts with digests; 2 distinct: 0a24 and 3029); raw traces for 96 runs were not kept, so the 100 were not individually re-hashed. Both digests are the 2 variants now covered. 3029968c76b3 is exactly the B-first variant.
