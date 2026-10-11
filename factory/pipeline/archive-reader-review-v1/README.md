# ArchiveByteReader independent review v1

Verdict: `CLEAR_SCOPED_WITH_TWO_NON-BYPASS_FINDINGS`.

`ArchiveByteReader` confines Mac refs to resolved admitted roots, uses `openat` + `O_NOFOLLOW` for every component, checks regular-file bytes, size & pinned SHA-256. Windows roots are keyed by exact canonical capture hash; proof role, nested host/runtime, compiler & per-run raw refs are hash-bound. Changed captures, unknown refs, tampered bytes & symlink escapes all block. No unrestricted-path, cross-capture or hash-forged-byte authorization path was found.

Evidence: fixture suite 5/5 passed. A real archived Mac capture was read offline from `factory/native/macos/evidence/20261010-gate-seeded/swiftui.image.recipe.gate-seeded.ca4e13f820f5d258/run-001/capture.json`: 3413 bytes, `sha256:4904b11ef20cbcf483d0b2d0d068a797212fa09671dec9c7e4c35b8c5511fee0`. This historical capture has no `meta.conditions.macOrigin`, so full nested Mac-origin admission remains unexercised by real capture bytes; current guard tests use invented fixtures.

Findings:

1. Test module explicitly says fixture-only; add one checked-in or pinned archive integration case with real `macOrigin` refs, including external `xcrun` map, `Witness.swift`, `CaptureHost.swift`, compiler receipt, binary & optional AX refs.
2. `_safe_relative` admits NUL. A malformed Windows proof path reaches `os.open` & raises `ValueError("embedded null character")`, while public reader contract promises `ArchiveReadError`. Gate catches this & blocks, so no authorization bypass; reject NUL in `_safe_relative` or normalize this exception.

Required archive conventions: Mac absolute logical refs must resolve under `macRoots` or exact `macPathMap` targets; Windows keeps one directory per bare canonical capture hash with `tool/compiler.bin`, `host/...`, `runtime/...` & observation raw files. Reader performs no compiler, GUI, Accessibility or permission request.

See `report.json` for hashes, commands & exact outcomes.
