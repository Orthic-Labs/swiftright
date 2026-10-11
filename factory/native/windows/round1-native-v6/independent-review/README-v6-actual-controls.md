# Native-v6 actual-controls review

Decision: **actual controls clear for root preference diagnostic**.

Final source stage `2647f8b51edfb4f44d78ca2540726f615a79d7004c98ae44d9441dbe389caa68` & source review `dbe07f506b060acc876baa3019d147bf4834e0fd2386d83190ca77014b3a7d2f` join 254 verified pins. Root fetched 16 files across 8 transfers; every listed file hash matches, all transfers exit `0`, control process exit `0`, & raw stdout/stderr hashes are retained.

Receipts pass: AST16/0 errors; namespace 2 positives + 5 faults; cleanup 15 rows with confirmed-exit/release gates; real stream copy/hash/idempotence plus unfinished/faulted rejection; close guard order with 7 faults rejected; exit proof 1 accepted + 11 rejected; hidden process stream exit `0`; startup 10 controls covering original 6-second breach, bounded 30-second diagnostic, exit priority, invalid durations, & typed exit state.

Root may proceed with pref diagnostic. Reviewer performed no SSH, GUI, Git, compiler, or native action.
