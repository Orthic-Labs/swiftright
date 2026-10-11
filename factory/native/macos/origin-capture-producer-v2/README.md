# Fresh F5 Mac origin producer v2

v1 source is frozen under `source-snapshot-v1/` with hashes recorded before repair. v2 closes review findings: fresh origin refs are archived into immutable per-case byte closure, compiler tools bind through exact hash aliases, checker invokes real reader-backed `mac_origin_admission_issues`, & output binaries require execute mode before SUCCESS.

`capture.py` archives every evidence file plus canonical case, source, adapter & output under `origin-archive/`. It writes `origin-reader-config.json` with explicit `macRoots` & `macPathMap`. Existing `compiler-tool-archive-v1` is reused only for matching tool hashes; gzip is decompressed to one shared 0644 raw cache, never mapped as raw bytes. Nonmatching tools require exact fresh bytes in shared cache. No native/compiler execution occurs in this packet.

`check_evidence.verify` loads per-case config, checks descriptor bytes/modes, then calls full Mac origin admission through `ArchiveByteReader` before reporting PASS. A malformed process/receipt cannot pass shallow joins. Main & auxiliary output binaries without execute bits abort item before fresh origin success.
