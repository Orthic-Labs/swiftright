# ArchiveByteReader actual Mac-origin replay v3

Decision: `CLEAR_SCOPED_ARCHIVE_REPLAY`.

Compiler-tool archive v1 passed offline integrity: xcrun 199024 bytes & compressed swift-frontend expanded to 173118384 bytes, both exact receipt hashes; tamper, truncation & traversal controls rejected. Expanded frontend lived only in ignored tool scratch during replay, then was removed. No installed tool bytes were read during replay & no native/compiler/GUI/Accessibility run occurred.

Using [config.example.json](config.example.json), production `load_origin_reader_config` & `ArchiveByteReader` read 130 mapped refs across five derived candidates. Main source, adapter, binary, compiler receipt, resolver/compiler streams, AX source/binary/receipt & exact archived compiler tools all passed `mac_origin_admission_issues` with zero issues. Original raw captures stayed untouched; run-001 hashes remain in [config-replay-result.json](config-replay-result.json).

This clears byte-reader/archive replay only. Candidate-only capture status, held channels & promotion boundaries remain unchanged.
