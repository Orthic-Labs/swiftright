# Tuple12 Windows incremental adapter v7

Source-only successor to v6 adapter. It preserves v6 helper, metadata, 54-file manifest, 42 source-file count, three edits, 1 GiB job memory, 8 MiB per-stream cap, 900-second deadline, retained handles, active-process proof, truthful restoration holds, & artifact-restoration-only receipt.

v7 moves stdout/stderr `CopyToAsync` readers before suspended child assignment & resume. It does not modify v6 helper or v6 sources. Root must refresh hashes, run source controls, then run native adapter on Windows.
