# Fresh F5 Mac origin producer v3

v3 repairs AVAILABLE auxiliary AX path binding. `fresh_ax_preflight` now emits exact copied source, executable & output-root compiler receipt paths. Origin descriptors & archive closure consume those fields directly; no per-case receipt or sibling-work reconstruction occurs.

Auxiliary receipt streams & compiler tool identities are archived from receipt fields. Main & auxiliary compiler tools each pass through exact hash-bound materialization before `ArchiveByteReader` verifies every capture. Offline control `test_aux_archive.py` uses distinct main/AX compiler paths, deletes all live inputs after archive creation & replays full `mac_origin_admission_issues` through durable bytes.

No native/compiler execution occurs in this packet. v2 source remains byte-frozen under `source-snapshot-v2/`.
