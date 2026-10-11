# Independent source review

Reviewed frozen source-stage manifest `a386a18fa3e14174e52ead92ef513503e2b2075f646c219d921bd05cd7fa0d57`.

The isolated worker source passes review for byte-identical `Read-UIA`, scalar-only parent boundary, exact target/window/lock ownership checks, background/no-activation behavior, retained-handle natural-exit check, sealed stdout/stderr requirements, and bounded fail-closed cleanup. `verify-source.py` passed and all 16 stage-manifest entries matched their pinned bytes and sizes.

This packet does not include production parent integration. Future caller must block pixels and `WM_CLOSE` until successful worker proof returns. No native Windows execution was performed.
