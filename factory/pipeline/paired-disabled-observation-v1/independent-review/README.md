# Independent offline review

This packet independently replays frozen `input-manifest.json` bytes & validates all 78 payload hashes, F9 case/source/probe joins, Windows plan/compile/native receipts, 20 Mac case/AX/layout/text joins, raw render interval channels, producer report references & held-status assertions.

Result is observational only: one Windows observation, 20 Mac observations, no qualified parity, no promotion. Mac raw AX has no enabled field; hit-testing has no invoke/callback receipt; qualified timing is unavailable; native/provider/occlusion/frozen-tuple channels remain held.

Run:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/pipeline/paired-disabled-observation-v1/independent-review python3 factory/pipeline/paired-disabled-observation-v1/independent-review/generate_review.py
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/pipeline/paired-disabled-observation-v1/independent-review python3 -m unittest discover -s factory/pipeline/paired-disabled-observation-v1/independent-review -p 'test_*.py' -v
```
