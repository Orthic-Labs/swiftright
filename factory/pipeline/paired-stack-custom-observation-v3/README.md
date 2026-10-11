# F9 paired stack & custom observation v3

`build_report.py` binds exact Mac20 summaries, native-v3 repaired single stack, original custom single, prior v1 four-attempt stack batch, cleanup-v2 one-attempt failure, & native-v3 fresh20 paths when present. Source/case hashes, per-run rows, raw inventories, statuses & missing inputs stay explicit.

Current native-v3 single stack is source-bound with UIA/PW evidence. Native-v3 fresh20 stack & custom paths are still awaiting real inputs. Cleanup-v2 attempted one stack run, failed before complete native packet, & remains unqualified; prior v1 four-attempt batch retains 3 valid rows plus one failure.

No attempts are silently excluded. Shape/layout semantics, parity, promotion & goldens remain held. Run `PYTHONDONTWRITEBYTECODE=1 python3 build_report.py --fault-controls` for source/case/raw/batch-count/status mutation rejection.
