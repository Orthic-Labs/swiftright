# SR1 current holds

Updated 2026-10-11.

- Fresh Mac r11 tuple `sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011` remains source-bound & unfrozen.
- Windows v10 full metadata controls passed baseline, relocated positive & 11 rejection faults; native qualification remains root-owned.
- New Mac common.schema packet is source-ready under `factory/oracle/mac/padding-origin-r11-source-v1/mac-common-schema-r11-v1/`.
- Supervised local verifier passed against exact fresh tuple, issued nonce `9ecd6b84d8a0429393909aba87743742`, source hash & source-binding bytes; controls passed baseline & rejected wrong tuple ID, source-binding ref, source hash, source archive, Mac host hash & Windows host hash.
- Local actual-inputs contained only `source-binding.json`, so sourceArchiveRef used same exact archived file; root must substitute any separate source archive when available.
- Paired parity, golden freeze & qualification remain held until root joins schema receipt with v10 coordinator receipt & actual observations.
- Count20 fresh r11 adapter packet is source-ready at `factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v11/`; Windows whole archive, strict proof joins & paired comparator remain pending.
- Legacy Count1 first-proof preflight resolved against explicit archive-root successor; failing ambient-root diagnostic remains historical & no raw files were relabeled.

## Next steps

1. Root runs verifier through `factory/tools/supervise-job.py` with factory venv Python & exact fresh inputs.
2. Root verifies receipt kind/version/status, nonce, source hash, tuple/case/host joins, schema/tool/source refs & zero effects.
3. Root passes receipt path/hash into v10 coordinator preflight; retain tuple unfrozen until paired comparison review.
