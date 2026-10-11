# F12 extended demand mapping v5

This additive packet preserves frozen v4 mapping (`mapping-v4.json` SHA256 `dc6ef940bab027639777c62dc7e1f657aaf777d5e702d7dee30cc74ca330ec0b`) & 107-row denominator. It records exact current Tauri/React/Rust source anchors for 24 of 32 residual rows; eight remain unresolved without exact source evidence. Three ambiguous rows remain ambiguous.

Source anchors prove host source ownership/use only. They do not select SwiftUI overloads, establish SDK identity, create registry links, or resolve full demands. `registryPromotion` & `newFullDemandResolutions` remain zero.

Replay:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v5/generate.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v5/test_mapping_v5.py
```

`test_mapping_v5.py` checks v4 row preservation, exact snapshot hashes & eight mutation controls covering denominator, row identity, promotion, ambiguous closure, source identity, line range & source hash faults.
