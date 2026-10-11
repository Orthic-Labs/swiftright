# Guarded internal compiler control failure

One fresh internal xcrun-swiftc control ran before any seed capture. It preserved actual resolver/compiler argv, PID/PGID, UTC timestamps, exit code, tool hashes, source snapshots & raw streams. Compiler exited `1` during link because minimal control source had no `main`; emitted binary is absent. No retry was made.
