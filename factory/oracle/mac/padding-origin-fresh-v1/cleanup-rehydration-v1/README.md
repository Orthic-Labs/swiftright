# Padding origin fresh v1 cleanup rehydration

Source-only successor for rehydrating archived compiler bytes after root-owned review. It preserves compressed archive members, verifies compressed/raw sizes & SHA-256 values, writes hash-named frontend bytes plus xcrun as regular 0644 data, & emits relative `ArchiveByteReader` mappings. Installed compiler paths are never read or used as fallback.

Current actual tool cache & internal scratch remain untouched. `rehydration-plan.json` records actual Mac20 review pin `sha256:c34df5ee099add13ed3f9a39cd2a2349f6edcb9f460a547f8a71680b4bc54a6f`; `offline-replay-plan.json` is not run in this packet. Root decides cleanup after review, rehydration receipt, & consumer mapping replay.
