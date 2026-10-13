# Fresh Count20 r11 issuer/guard/launch source-v2

This packet binds Count20 metadata to fresh r11 case `037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de`, tuple `sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011`, fresh manifest bytes, v4 source-equivalence receipt, and measured donor compile closure. It leaves donor Count20 namespaces untouched.

`issue-count20-fresh-r11.ps1` validates fresh case/tuple/manifest bytes, v4 admission, actual plan/receipt/executable hashes, runtime/renderer joins, then writes fresh candidate tuple/binding/context, 20 prefixed IDs, and metadata under caller-supplied fresh `NamespaceRoot`. It refuses existing output/run paths.

`guard-count20-fresh-r11.ps1` validates issued metadata, all tuple/binding/context joins, v4 receipt, actual closure, runtime modules, and 20 IDs. Output is source-only guard receipt.

`launch-count20-fresh-r11.ps1` verifies issuer/guard/equivalence/stage hashes and fresh namespace, then delegates to caller-supplied reviewed namespace-aware coordinator. It never substitutes historical donor paths.

Run pure controls:

```sh
factory/.venv/bin/python factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v2/test-count20-fresh-r11.py
```

Root-controlled Windows sequence: transport this packet, fresh r11 case/tuple/manifest, v4 receipt, actual plan/receipt/executable/renderer/source closure, and repeat-r7 stage sources; run issuer into new rolling `.factory-work` producer/coordinator namespace; run guard; run launch recipe with coordinator overlay whose repeat-r7 source bytes match stage manifest. Existing `observed-count20-metadata-r7` and `observed-native20-r7` remain historical donor evidence.
