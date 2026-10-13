# Text Count20 r9 cleanup review v4

Cleanup-only source packet for held Text Count20 r9. It preserves original failure & never promotes qualification. Five pinned identities are checked: coordinator parent, two renderer hosts, & two UIA workers. Worker inventory hashes are checked before current-state inspection.

`cleanup-current-quiescence-v4.ps1` verifies identity/source/task/coordinator pins, coordinator parent proof, each available original terminal certificate, 1 GiB memory bound, exact PID+path+native start time+EXE hash, & native waits. A current PID absent from managed enumeration is accepted only with native `OpenProcess` failure `ERROR_INVALID_PARAMETER` 87. This proves current absence only; it does not create original terminal proof. A reused or mismatched PID is never terminated.

If all five identities are currently quiescent, script performs exclusive expected-owner CAS on lock. With native-02 lacking original terminal proof, receipt status is `cleanup-quiescent-current-absence-qualification-held`, with `currentQuiescent=true`, `originalTerminalProof=false`, `qualificationClaim=false`. Original held receipts remain unchanged.

Prior cleanup hashes stay distinct: inner receipt `2fd77664984b7561af5541a467c061174e92e3c25e46c8e797576f7004547f74`; outer wrapper stdout `2bafb953c241714cc8efc79de235d4b55ba3339e8d43d16878fc15004d360064`.

Root runs one bounded PowerShell invocation after staging explicit paths:

```powershell
& .\cleanup-current-quiescence-v4.ps1 `
  -EvidenceRoot D:\Claude\swiftright `
  -IdentityPath factory\pipeline\text-count20-r9-cleanup-review-v4\identity-input-v4.json `
  -IdentitySha256 <identity-v4-sha256> `
  -CoordinatorPath factory\native\windows\.work\text-mta-r11-count20-r9\control-count20-r5\coordinator.json `
  -CoordinatorSha256 72b872b2e87b2bb239e68c6ce33ae8a2b895f4fd19c72aedad5479e3e304cb6a `
  -TaskResultPath factory\native\windows\.work\text-mta-r11-count20-r9\control-count20-r5\task-result.json `
  -TaskResultSha256 fdea9ecef57d92e8d988cfb99ca8b7ec5f65572ce08537310431dffae84120e2 `
  -SourceInputsPath factory\native\windows\.work\text-mta-r11-count20-r9\admission-count20-r5\source-inputs.json `
  -SourceInputsSha256 6c335ddead9c023b1faf40bc9e02fb679112f48ec1955934dd28ce4268789c22 `
  -LockPath D:\Claude\desktop.lock `
  -ExpectedOwner 'factory-rectangle-9526f6f062a841d69ec4a860f4b4cd03 2026-10-12T03:57:15.1903850+00:00' `
  -OutputPath D:\Claude\swiftright\.factory-work\text-count20-r9-cleanup-v4\receipt.json
```

Expected successful cleanup-only status is `cleanup-quiescent-current-absence-qualification-held`; nonzero exit means no CAS occurred or current quiescence failed.
