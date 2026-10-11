# Seeded build v2 actual-controls review

Decision: **actual-controls clear for root compiler**.

Reviewed root-fetched receipts against source stage `a9d53bdb2872ac8bccdd437104d107e4d1e37ba787735ecff41ab2d90db7f03f`. SCP manifest has 111 files, both transfer exit codes are 0, every listed file hash matches, control process exit is 0, stdout/stderr hashes are retained, & source process is separate from this read-only review.

Observed controls: cleanup 3 positive + 3 faults; host-input 5 faults with normal path passing; parse 9 rows + 0 errors; integer admission 2 Int32 + 2 Int64 positives + 9 typed faults; reserved-assignment lint pass across 10 files with 0 assignments; production admission actual outputs + positive fixture pass with 7 faults rejected. Control receipts report 0 compiler invocations & 0 native calls.

All five frozen seed plans join source-admission metadata & source bindings: custom-layout, padding-frame, preference-key, scroll-view, & stack-overlay. Their plan hashes & shared runtime metadata hash are recorded in `report-v2-controls.json`.

Root may continue into compiler gate using frozen builder `0f50a0d8653d1869538b4d79bc143168adac2ee2c42b9bb0f8760cf9bcee44f4`, admission helper `0348814bba0e8ea89de323603bcd096f10b68528a0ac762c1df9078e624fa39e`, & control runner `dc22324f148b5da18e2d599e097b039a6478074366fbbfaeed9be4099a7723cc`. Reviewer performed no compiler, native, SSH, or GUI action.
