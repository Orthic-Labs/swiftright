# Count20 repeat successor r1

Source-only successor for Count20 after accepted Count1 `execute-r3`. Frozen Count1 producer files remain unchanged. This packet binds existing `capture-plan.json` `dispatch.repeat` (`count:20`, `runRoot:actual-repeat-r1`, `firstProofRequired:true`, `retries:false`), consumes preissued metadata plus full metadata guard/schema receipts, then invokes child overlay chain `resume -> interactive -> dispatch -> capture`.

Install child files under `root-metadata-controls-v2/repeat-r1` on Dell. Each script resolves frozen capture-v3 root from `$PSScriptRoot\..\..`; child scripts are selected through `$overlayRoot`. Coordinator control folder is capture-v3 `coordinator-repeat-r1`; fresh output is capture-v3 `actual-repeat-r1`.

Run offline source admission on Mac:

```text
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r1/test-repeat-source.py
```

No Count20/native claim is made until root completes Count1 adapter success, transports exact receipts, reviews this packet, & executes Windows effects.
