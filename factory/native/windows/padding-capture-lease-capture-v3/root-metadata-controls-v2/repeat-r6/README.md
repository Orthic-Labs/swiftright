# Count20 repeat-r6 source successor

repeat-r6 copies repeat-r5 with only suffix/path changes plus first-proof metadata namespace repair. Frozen repeat-r5 remains preserved. Native, compiler, lock, remote, & GUI actions are zero in source controls.

`support/first-proof-repeat-r6.ps1` requires copied `actual-single-r1/issued-metadata.json` bytes to equal canonical `coordinator-single-r1/issued-metadata.json` bytes, then calls `Assert-LeaseIssuedMetadata` against canonical coordinator path. This preserves candidate tuple/binding lookup under coordinator namespace.

Source controls:

```sh
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6/test-repeat-r6-source.py
```

Root installs five pinned overlay files under `root-metadata-controls-v2/repeat-r6`, installs helper under capture `support/`, parses source, runs prelaunch controls, then uses existing preissued Count20 metadata. Native archive remains held until actual run completes & every declared ref is byte-sealed.
