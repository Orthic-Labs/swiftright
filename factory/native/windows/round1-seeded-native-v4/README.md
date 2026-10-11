# Seeded native v4 factory repair

Clones frozen v3 source inputs & unchanged source proof. Runtime, renderer, ABI, host witnesses & frozen host plans unchanged.

Retained kernel exit certification requires typed boolean flags, integer WAIT_OBJECT_0 value0, exact certification kind & successful terminal status. HasExited remains diagnostic. Missing original retained certificate fails coordinator lock release closed.

Process exit deadline15s & raw copy deadline5s remain unchanged. Destination Flush(true)/Dispose have separately reported5s closure deadline on dedicated managed background thread. Pending copy skips explicit flush. Sealed raw requires successful copy, successful required flush, confirmed destination closure & no closure error.

Controls retain existing eight entries. test-kernel-bounds.ps1 -OutputRoot <fresh-path> adds incoherent raw kernel/status proof rejection; hidden console384KiB exact stdout/empty stderr; explicit inherited writer holding both EOFs after primary kernel exit. Inherited-writer case emits64KiB exact bytes, calls production pending-copy closure helper, checks diagnostic states & stable bytes/hash, then releases writer & settles copy tasks. Holder has independent15s bound. test-stream-seal.ps1 includes actual failed Flush(true) plus successful Dispose rejection.

Exit/stream failure receipts use Flush(true) before destination closure. Failed-copy hashes remain diagnostic partial bytes; transport stays CopyToAsync.

Windows PowerShell5 AST & actual controls are pending root execution. Stage is ready for independent source review.
