# Independent review: seeded five-case observation v2

Offline review of frozen stage `91d219406e4dfbdccb7c7aa0b804c140adef39bf3bd5812b7906308e7e7f0374`. Review script re-hashes every staged file & each referenced Mac/Windows raw inventory, then checks 100 Mac run raw/capture bytes against immutable proof & lineage rows, five one-run Windows cases against source/case/executable/capture fields, UIA labels, and held-status boundaries. Producer `--fault-controls` baseline passed with 8/8 controls rejected; independent report mutations passed with 10/10 controls rejected.

Reviewed outcome: 20 Mac runs per case (100 total), five Windows singles, exact source/case joins, 100 proof-linked raw streams & 100 proof-linked captures. Stack, padding & preference exact role-mapped labels are observational only. Custom remains empty/held because no AXStaticText exists; scroll keeps raw labels but instrumented status is UNOBSERVED for all 20 runs, so no sequence match. Compiler OS origin, parity, qualified timing/paint, goldens & promotion remain held.

`fetchComplete` values 32–34 match Windows output-fetch file counts, rather than Mac run counts. Four Windows review receipts directly bind those fetched lists; scroll receipt remains `pending-review`, with 34 corroborated by existing root SCP log. This field does not affect 100/5 observation denominator. Seeded v1 namespace mismatch diagnosis remains preserved in its own review packet.

No producer files, source reports, Mac evidence, Windows evidence or historical v1 packets were changed.
