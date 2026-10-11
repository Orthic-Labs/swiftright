# SR1 memory incident, 2026-10-11

User killed Python PID 29434 after observing about 46 GB memory & 29.4 GB swap usage on a 24 GB Mac.

SR1 subagent launched a Python stdin script at 15:29:22 UTC (20:59:22 IST). Codex command session 98965 ended failed at 16:30:16 UTC after 3,653 seconds. Its loop searched each bridge manifest hash by traversing `Path('.').rglob('*')` & calling `hashlib.sha256(p.read_bytes())` on every file except `.git`. It included ignored scratch & VM files. Root failed to supervise this outstanding command.

Two included files have logical sizes of 50,000,000,000 bytes each: `factory/.tart/vms/sr1-capture/disk.img` & `factory/.tart/vms/base-snapshot/disk.img`. Whole-file reads of these disks explain observed allocation. Which disk was being read at termination was not retained. No source-map verification needed either disk.

Recovery: user terminated offending process; root verified PID absent & no SwiftRight Python process remaining. Both source agents paused. No rerun of broad search.

Prevention: `factory/AGENTS.md` now requires explicit source scopes, scratch/VM exclusions, streaming hashes, pre-read size limits & supervision of yielded sessions. `factory/tools/hash-explicit-files.py` enforces 64 MiB per file, 256 MiB total, 256 files & 60 seconds with 1 MiB reads. Its controls verify exact streaming SHA256, large sparse-file refusal before read, explicit VM-disk refusal & symlink refusal.
