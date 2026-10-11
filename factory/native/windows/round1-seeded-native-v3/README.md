# Seeded native v3 factory repair

Cloned v2 immutable factory sources & unchanged Mac source proof. Runtime, renderer, ABI, plans & witness bytes unchanged.

Owned exit requires retained kernel handle signal. HasExited is diagnostic. Missing retained kernel certificate fails coordinator lock release closed, including absent-PID lookup. Exit deadline remains15s; raw stream deadlines remain5s.

Raw copy completion, destination closure & sealed qualification are separate. Failed stream hashes are diagnostic partial bytes. Exit/stream failures receive Flush(true) diagnostic receipts before destination closure. CopyToAsync transport unchanged.

Controls: existing eight entries plus test-kernel-bounds.ps1 -OutputRoot <fresh-path>. New entry runs fake HasExited-without-signal, kernel wait failure, proof gates, hidden console384KiB exact stdout with empty stderr, & explicitly inherited writers holding both EOFs after primary kernel exit. Holder has15s independent bound; gate release restores EOF with5s waits.

No actual Windows controls or GUI runs performed in this stage. Root runs frozen sources through Windows PowerShell5 parse & actual controls before replay admission.
