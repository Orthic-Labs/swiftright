# F12 extended demand mapping v6

V6 is additive source audit over frozen v5 (`mapping-v5.json`); denominator remains 107. Five residual rows remain unresolved after exact byte/hash inspection of archived host source snapshots; three catalogue rows remain ambiguous. Snapshots contain no `import SwiftUI` or registry selector, so no exact SDK declaration, overload, registry link, or full demand resolution is claimed. SDK archive resolution and registry promotion remain zero.

Replay:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v6/generate.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v6/test_mapping_v6.py
```

Seven controls reject denominator, row, promotion, base hash, source marker, snapshot hash & ambiguous-closure faults.
