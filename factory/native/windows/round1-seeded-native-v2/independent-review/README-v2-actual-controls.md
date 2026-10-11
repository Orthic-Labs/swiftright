# Seeded-native-v2 actual-controls review

Decision: **actual controls clear for root seeded single**.

Root control process exit `0` (`2026-10-11T05:26:52.205785+00:00` → `2026-10-11T05:26:58.260633+00:00`). SCP manifest lists 17 files across 8 successful transfers; local verification found 0 missing & 0 hash mismatches. Raw control stdout/stderr hashes are retained in report.

Actual receipts pass: 16 AST rows with 0 errors; namespace 2 positives + 5 rejected faults; cleanup 3 confirmed exits plus identity/timeout/priority/release controls; stream seal copy/read/hash/idempotence plus unfinished/faulted rejection; close ordering with 7 rejected faults; exit proof 1 accepted + 11 rejected faults; hidden process stream child exit `0` with confirmed owned exit; Mac proof 1 accepted + 24 rejected faults, including changed bytes, duplicate run, wrong seed fields, bool scope, receipt fields, & status.

Five-host Windows compiler review is joined by stage `c568ac509539d7108e76429c60efee409066f979636997c116ef1614486fe00e` & final receipt `1a400a86a73a7aa3ddc42b043bb96a77c34453d46498578b8abfffbde63545d0`. Root may proceed with seeded single gate; GUI/native dispatch remains separately gated.
