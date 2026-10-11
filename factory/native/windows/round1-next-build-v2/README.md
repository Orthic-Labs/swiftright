# Versioned next-host compiler-only builder v2

Reuses exact frozen padding-frame/preference-key v1 packages & pinned plan hashes. Fresh `build-v2-r1` per package; no runtime/bridge/witness edits, executable launch, GUI or desktop calls.

Captured stdout/stderr use raw BaseStream copies. Durable observation exists before launch & before cleanup. Retained kernel process handle identifies owned driver; natural exit never triggers termination. Deadline uses TerminateProcess on that retained handle, then bounded wait/drains. No PID-based taskkill or Get-Process lookup. Root-only termination explicitly leaves descendant ownership unresolved; unsuccessful control refuses next build pending external ownership resolution. This helper does not claim atomic process-tree cleanup.

Prepared controls call production cleanup decision: natural exit, exit-at-deadline, owned timeout; unknown wait status, failed wait & running-without-abort reject. AST controls parse production & controls. Both controls remain unexecuted in source packet; root runs controls before single fresh compiler build for each package. No build/test run occurred during preparation.
