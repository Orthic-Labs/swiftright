# F9 paired stack & custom observation v2

`build_report.py` consumes exact Mac20 summaries, original Windows attempts, repaired single stack capture, historical four-attempt stack batch, & real cleanup-v2 paths when present. Every plan, observation, case hash, source hash, dispatch status, run index, native packet & raw inventory stays bound; missing inputs remain explicit.

Current report separates original Overlay failure, historical v1 custom/single & failed four-attempt stack batch, repaired stack single, & prepared cleanup-v2 fresh20 inputs. Historical batch retains 3 valid success rows & masked cleanup failure; no attempted row is dropped. Current fresh20 Windows qualification is false until both real per-case batches contain 20 exact valid runs.

Shape/layout semantics, parity, qualification & goldens remain held. Run `PYTHONDONTWRITEBYTECODE=1 python3 build_report.py --fault-controls` for source/case/raw/batch-count/status mutation rejection.
