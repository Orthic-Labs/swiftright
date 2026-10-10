# Fixed 81 Foundation snapshot

Fresh `factory/probes/generator.py` output for pinned 81 pipeline cases, bound to runtime commit `bbceb5a14cab2be125af68f8e84014a29f3277a7` & source tree hash recorded in `lineage.json`.

F7 source sweep input is [manifests](manifests), which contains 81 manifests & co-located Swift sources. Matching review copies are in [sources](sources). `lineage.json` records original/current source & manifest hashes, recipe/case hashes, classifications, & equal Mac/Windows source bindings.

Run verification with:

```sh
factory/.venv/bin/python factory/pipeline/corrections/fixed81-foundation-20261011/verify.py
```

Verifier requires 14 Foundation-only positive deltas, exact existing primary correction bytes for custom-layout & preference-key, expected-negative compile failures, current generator witness metadata, & no unplanned source changes.
