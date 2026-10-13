# Prospective Count20 metadata/resume packet

This packet is source-only. It requires Count20, preissued metadata in `coordinator-batch-r1`, full metadata guard receipt, & Mac `common.schema` receipt before invoking native dispatch. Count1 remains immutable & must produce first-capture proof before Count20.

`capture-plan.json` currently exposes `dispatch.repeat` only. Packet requires reviewed `dispatch.batch` with `actual-batch-r1`; it fails closed while field is absent. `coordinator-batch-r1` remains distinct. No Count20 launch is admitted by this packet until batch plan/dispatcher integration is pinned.

`resume-batch-issued-coordinator.ps1` skips issuer only after all receipts pass, then invokes copied Count20 wrapper, dispatcher, & capture runner bound to prospective `dispatch.batch`. `issue-batch-before-launch.ps1` allocates Count20 metadata under batch control namespace. `test-metadata-guard-controls.ps1` exercises actual baseline, relocated positive, & 11 resealed faults against frozen producer guard. `verify-common-schema.py` validates exact tuple/schema/source/archive joins.
