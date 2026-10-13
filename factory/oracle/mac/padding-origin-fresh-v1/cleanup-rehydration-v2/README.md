# Padding origin fresh v1 cleanup rehydration v2

v2 binds frozen compiler-tool archive manifest version as exact string `"1"`; booleans, integers & unknown strings reject. Rehydration verifies compressed/raw archive bytes, writes hash-named frontend & xcrun as regular 0644 data, preserves current raw-cache consumer mapping, then reads all mappings through production `load_origin_reader_config` + `ArchiveByteReader`.

One archive-only replay passed with PID 68959, exit 0, current tool reads 0, native/compiler executions 0. Output remains in fresh internal cache `cleanup-rehydration-v2-actual`; existing actual cache & scratch were not deleted. Replay receipt & output hashes are pinned in `rehydration-plan.json`.
