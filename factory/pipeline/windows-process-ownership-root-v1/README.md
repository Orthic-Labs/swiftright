# Owned inspector cleanup

Actual Windows inventory at 2026-10-11T22:46Z found three root-owned PowerShell inspectors left running after local SSH deadlines. PIDs39956,61012,37000 together held about16.8GiB working set. Exact encoded command hashes, process start identities & prior root invocation bytes establish ownership; unrelated processes were preserved.

Each cancellation opened & retained its original process handle, rechecked image/start/full-command/encoded-command identity, terminated only matching process, then obtained a bounded kernel terminal certificate. `inventory-r2.json` confirms all three gone. Cancellation receipts & allowlists preserve exact identities. Eight older small PowerShell processes had no established root ownership & were untouched.

Local SSH supervision alone did not bound remote process lifetime or memory. Prospective root transport now admits Windows PowerShell & descendants to a256MiB job before reading or invoking supplied script, retains child handles, limits streams to8MiB each, enforces monotonic deadlines, stops owned descendants & records sealed streams plus final self-only membership. Actual controls cover exit0, timeout/descendant cleanup, foreign-process survival, output cap & wrong source hashes. Compiler transport uses explicit1GiB aggregate cap; native scheduler jobs independently enforce1GiB.

No speculative source cause is claimed for inspector growth. Recursive PowerShell object serialization remains a diagnosis lead. Raw receipts remain unchanged. Factory jobs no longer use arbitrary uncapped EncodedCommand inspectors.
