# ArchiveByteReader actual Mac-origin replay v2

Decision: `BLOCKED_MISSING_ARCHIVED_TOOL_BYTES`.

Derived candidate objects referenced five untouched v2 capture summaries, cases, compiler receipts, source snapshots, binaries & AX receipt/source/binary. `ArchiveByteReader` read all mapped archived bytes through config-backed roots/remaps. Each case then held on exactly two missing receipt inputs: `/usr/bin/xcrun` (`sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9`) & `/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend` (`sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7`). Neither tool byte is present in `archive-map.json`; no current SDK/tool stand-in was read.

This is diagnostic replay only. Original capture files remain unchanged & their run-001 hashes are recorded in `report.json`. No native, compiler, GUI, Accessibility or permission API ran.

`config.example.json` binds actual archive root plus 17 exact internal scratch/AX logical paths. Add exact archived xcrun & swift-frontend bytes, then map those two logical paths to complete replay. Current config intentionally remains blocked closed.

Focused reader tests: 5/5 pass. Reader config tests under `factory/.venv/bin/python`: 6/6 pass.
