# Fresh Count20 r11 coordinator overlay source-v4

v4 preserves v3 source lineage & fixes issuer publication. Issuer creates parent namespace only, then uses `CreateNew` for candidate tuple, binding, context, and metadata; existing files fail closed. Corrected v3 issuer/guard/launch remain historical source. v4 guard uses raw case hash `f9a8e685f55c8063fde159bfb58926c637cd740fc8c6edb71de702933b7e3878` while semantic case hash remains `037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de`.

`integration-fresh-r11-v1.ps1` retains frozen integration helpers, including first-proof predicates, & replaces only source-root binding with fresh-root containment. Stage it beside fresh overlay under producer root layout where `..\\..\\support\\integration.ps1` resolves frozen support bytes. Sequence is v4 issue -> v4 guard -> v4 launch gate -> fresh coordinator -> interactive task -> dispatch -> capture.

Measured hashes remain full: Mac `sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777`; Windows EXE `sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10`. Source map includes every overlay/helper hash & zero effects.

Offline controls:

```sh
factory/.venv/bin/python factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v4/test-count20-fresh-r11-v4.py
```
