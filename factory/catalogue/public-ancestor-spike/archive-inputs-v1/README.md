# F1 archive-inputs-v1

Frozen resolver input mapping for public-ancestor compiler evidence. `archive-input-mapping.json` binds each original semantic absolute path to exact whole SHA-256 & bytes, then to one repository-relative plain or deterministic gzip archive. SDK root remains directory-only execution prerequisite; no whole SDK/cache copy is staged.

Inputs are derived from frozen clang nominal stage, clang owner guard, Swift 16 archive manifest, & destructor archive manifest. Clang 124676976-byte tool is stored as `gzip -n` bytes below 100 MB; Swift compiler reuses previously checked `swiftc.archive.gz` whose decompressed bytes/hash are pinned. Existing source/tool archives are referenced by explicit repository paths; missing small SDK headers/interfaces are copied with hash-prefixed names.

Run `python3 verify_archive_inputs.py` for strict positive checks. `python3 -m unittest -v test_archive_inputs.py` exercises altered semantic/archive hashes, missing paths, duplicate identities/aliases, gzip whole-hash, SDK-copy, & path-escape faults.
