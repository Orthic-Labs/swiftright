# F10 trusted reader observation v1

This source packet consumes existing Mac20 report bytes & typed Windows20 adapter output. It requires exact `windowsArchives` capture-hash joins & `meta.conditions.windowsExitProof` on every Windows capture. Each capture passes production `ArchiveByteReader` plus `verify_windows_exit_admission`; no raw path fallback exists.

Root-only command after Count20 adapter output & archive transport:

```sh
factory/.venv/bin/python factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/trusted-reader-report.py \
  --input <f10-input-manifest.json> \
  --output <fresh-output/report.json>
```

Input manifest exact fields: `version=1`, `expectedWindows=20`, `macReport`, `windowsCaptures`, `macRoots`, `macPathMap`, `windowsArchives`. Every physical path is relative to manifest directory. `windowsArchives` keys are bare lowercase canonical capture hashes; values are admitted archive roots.

Successful output records 20 Mac origin-proof facts & 20 reader/admission evidence rows. `comparison` remains `held-observation-only`, with semantic/timing/native parity/goldens/promotion held. Source packet performs no native, compiler, remote, lock, or source-mutation action.
