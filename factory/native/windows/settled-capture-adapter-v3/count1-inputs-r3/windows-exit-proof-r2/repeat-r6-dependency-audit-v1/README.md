# Repeat-r6 first-proof dependency audit

Source-only audit records transitive imports required before `Assert-PaddingFirstCaptureProof`. Missing `uia-worker/schema.ps1` caused Count20 preflight failure because `Assert-UiaSnapshotWorkerProof` was undefined. Load cleanup & stream helpers first, then renderer/worker exit certificates, schema, all-owned-release, integration guard, & first-proof. Capture runtime loads `invoke-worker.ps1` after preflight. No source or frozen r6 launch file changed.
