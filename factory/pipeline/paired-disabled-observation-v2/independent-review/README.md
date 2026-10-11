# Independent v2 review

Offline replay verifies frozen 1,131 input bytes & hashes, six channel scopes, F9 source/case/probe joins, three separate 20-run batches, raw Mac AX enabled bools, historical Mac paint separation, Windows UIA bools & PrintWindow repeat joins.

Semantic mapping is explicit: Mac `AXButton`/`Continue`/`AXEnabled.value` bool true ↔ Windows `ControlType.Button`/`Continue`/`IsEnabled` bool true. Batches remain independent; no run-to-run pairing is asserted.

Qualification remains held: zero accepted golden cases, native parity held, timing held, hit-testing held-not-attempted, controlled occlusion held-unqualified, frozen tuple held-unbound, promotion none.

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/pipeline/paired-disabled-observation-v2/independent-review python3 factory/pipeline/paired-disabled-observation-v2/independent-review/generate_review.py
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/pipeline/paired-disabled-observation-v2/independent-review python3 -m unittest discover -s factory/pipeline/paired-disabled-observation-v2/independent-review -p 'test_*.py' -v
```
