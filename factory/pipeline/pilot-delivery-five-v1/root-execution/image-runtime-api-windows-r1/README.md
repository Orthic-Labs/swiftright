# Image additive runtime Windows headless lane r1

Root-only execution entry for current uncommitted runtime API closure. It uses canonical rolling runtime stage, no `hosts` directory, no GUI, & one bounded SwiftPM lane.

Using existing transport, stage only `probes/sr0-s/fresh-runtime` into:

```sh
scripts/sync-to-win.sh probes/sr0-s/fresh-runtime 'D:\Claude\swiftright\.factory-work\runtime-stage\runtime'
```


```text
D:\Claude\swiftright\.factory-work\runtime-stage\runtime
```

Run `run-headless-tests.ps1` inside existing pinned Windows supervisor with 1 GiB RSS, 120 s wall budget, sealed stdout/stderr, & job quiescence. Script refuses noncanonical runtime path & preexisting scratch. It runs:

```text
swift.exe test --package-path D:\Claude\swiftright\.factory-work\runtime-stage\runtime --scratch-path D:\Claude\swiftright\.factory-work\runtime-stage\runtime-api-image-r1-scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1
```

No UI or renderer/bridge is involved. `source-manifest.json` pins six additive files. Parent stage must be quiescent before overlay; preserve prior receipts & do not delete remote material.
