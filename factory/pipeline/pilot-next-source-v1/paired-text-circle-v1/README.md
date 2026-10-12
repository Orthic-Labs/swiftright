# Paired Text/Circle reader v1

Source-only adapter for explicit Mac20 & Windows20 archives. `compare_paired.py` verifies canonical case, tuple, source, recipe, compile receipt, executable, renderer, per-run capture/image IDs, raw identities, sealed parent certificates, bounded PNG summaries & profile metrics.

Run from repository root after root supplies fresh manifest:

```text
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/paired-text-circle-v1/compare_paired.py --input <fresh-input.json> --output <fresh-report.json>
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/paired-text-circle-v1/compare_paired.py --input <fresh-input.json> --controls --output <controls.json>
```

Manifest profile is `text` or `circle`. Text requires 120x48 DIP, font, wrap, compositor & titlebar metrics. Circle requires 320x240 DIP, `system.blue`, frame, placement & clip metrics. Circle AX remains recorded as supplied; AX absence stays diagnostic evidence. Reports remain `observed-diagnostic`, `semantic=held`, `timing=raw-only`, `parity=held`.

`input-template.json` is shape-only. Root must fill exact measured canonical refs & 20 rows from supplied Text `observed-style-mac20-r3` or Circle `observed-mac20-r1` plus matching Windows final archive. Null fields are intentional; template is not evidence.

Reader limits JSON to 2 MiB, each evidence file to 64 MiB, each image to 8 MiB, total distinct evidence to 256 MiB, & pixels to 4M. Hashes stream in 1 MiB blocks; symlink components, missing rows, wrong joins, wrong IDs, wrong bytes, wrong parent certificates & malformed metrics reject before report publication.
