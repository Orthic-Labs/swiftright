# Next-case paired observations v1

This packet compares exact source-bound accessibility observations for three
cases. Each row has 20 existing Mac runs and one fresh Windows native
observation; it is not a 20-run Windows batch. Inputs are pinned by
`source-inputs-v1.json` (SHA-256
`7ac004e1aa4e250e14b5b604eaffc450defa366addcc10608a828b61cb3d79d1`). The
manifest binds 409 raw files from the exact Mac and Windows packets.

The report preserves Mac external AX labels, compositor captures, Mac clock
records, Windows UIA, PrintWindow/screen PNG hashes and raw Windows task/compile
timestamps. Only explicit `AXStaticText` → `ControlType.Text` labels are
compared. All three current sequences match: `Box`; `0`, `1`, `2`; and `Row 0`
through `Row 3`. Mac uptime and Windows compile timestamps remain separate;
provider pixels are not normalized or compared.

Run from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s factory/pipeline/paired-next-observations-v1 -v
PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-next-observations-v1/generate_report.py
```

The report status is `source-bound-observation-only`. Native parity, timing
parity, pixel parity, controlled occlusion, hit-testing, provider readback and
accepted-golden count remain held or untested. AX label agreement does not
prove click behavior or rendering parity. Existing Mac 20-run packets and
single Windows receipts remain untouched; later Windows repeat batches belong
in a separately versioned packet.
