# Count1 coordinator r2 source repair

This packet supersedes only prospective `resume-issued-coordinator.ps1` source. Executed r1 source remains immutable. r2 checks root-stage manifest `sha256` + byte fields before lock declaration, then retains all r1 metadata, schema, first-proof, worker, quiescence, & release gates.

Run source admission before native launch:

```bash
python test-resume-source-admission.py \
  --source-root factory/native/windows/padding-capture-lease-capture-v3 \
  --actual-root factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1
```

Admission binds archived Count1 issued metadata, full guard receipt, review hashes, Mac schema nonce/tuple joins, & zero native/lock actions. It does not acquire lock, start task, invoke PowerShell, or launch native host.
