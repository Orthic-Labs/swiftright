# Seed compiler-origin source packet v2

New immutable source packet; seed-origin-v1 remains untouched.

Seed `14577611000270672472`, exact five corrected inputs. `capture_origin.py` retains original xcrun-swiftc policy by default, preserving logical `swiftc` invocation name while recording resolved real compiler path/hash separately. Optional direct mode preserves logical symlink path without `.resolve()` substitution.

Compiler & resolver processes use owned process groups, bounded communicate drains, TERM then KILL, durable stdout/stderr/error receipts & nonfatal missing-group race records. Source/tool drift blocks success.

`verify_receipt.py` rejects logical argv substitution, resolver/compiler mismatches, PID/group/timestamp/exit faults, raw stream/hash drift, source drift, tool drift & missing binary.

One separate guarded internal compiler control ran once; it failed at link exit 1 due minimal source lacking main. Failure receipt is archived under control/failure-20261011; no retry was made. No seed capture/build has run from v2.
