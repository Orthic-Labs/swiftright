# Text Count20 r9 cleanup review v3

This packet performs cleanup evidence only. It never changes `D:\Claude\desktop.lock`, never promotes r9, & preserves original failed receipts.

Measured evidence shows coordinator failed with parent kernel wait 0 / signed exit 1, task result held with 335,839,232-byte peak under 1 GiB, native-01 PID 50080 has pinned original terminal+sealed-stream proof, & native-02 PID 26108 has no original terminal certificate. Prior cleanup receipt `2fd77664984b7561af5541a467c061174e92e3c25e46c8e797576f7004547f74` recorded both PIDs absent, zero termination, zero lock actions, & `cleanup-held`.

`cleanup-review-v3.ps1` adds current absence proof: managed `Get-Process` absence plus native `OpenProcess` zero with `ERROR_INVALID_PARAMETER` 87. It accepts absent PID only when pinned original terminal evidence also validates. Live PID handling opens one native handle, validates exact PID/path/native start ticks/executable SHA, allows wait 0 or 258 only, terminates only exact matching identity at wait 258, waits terminal, reads native exit code, & closes handle after receipt data is formed. Reused or mismatched PID stays held.

Root runs one bounded cleanup review after staging explicit files:

```powershell
& .\cleanup-review-v3.ps1 `
  -IdentityPath .\identity-input.json -IdentitySha256 <identity-sha> `
  -CoordinatorPath <actual-r9-coordinator.json> -CoordinatorSha256 72b872b2e87b2bb239e68c6ce33ae8a2b895f4fd19c72aedad5479e3e304cb6a `
  -TaskResultPath <actual-r9-task-result.json> -TaskResultSha256 fdea9ecef57d92e8d988cfb99ca8b7ec5f65572ce08537310431dffae84120e2 `
  -SourceInputsPath <actual-r9-source-inputs.json> -SourceInputsSha256 6c335ddead9c023b1faf40bc9e02fb679112f48ec1955934dd28ce4268789c22 `
  -OutcomePaths <native01-outcome.json>,<native02-outcome.json> `
  -OutcomeSha256s 6021dfdab7ab245976dcc88cbbd6d7642ce64a684a65f9d8c4ef628bc916c3b9,60ebf282f7d16b48a4eb6d9408fcd1574addc49459376f9d9e7e4db209e47a55 `
  -InventoryPaths <native01-inventory.json>,<native02-inventory.json> `
  -InventorySha256s 5605275d710cd041872674c94cbfe9f8c90a34e4cde3b711eb2533f3ca1cc186,3c40c9f1b47b0e0ccdc2d2134968de55c65d7e225466ac31cd7a3bfd76ec719f `
  -LockPath D:\Claude\desktop.lock `
  -ExpectedOwner 'factory-rectangle-9526f6f062a841d69ec4a860f4b4cd03 2026-10-12T03:57:15.1903850+00:00' `
  -OutputPath <fresh-output.json>
```

Expected current state is `cleanup-held` until native-02 gains independently valid original terminal proof. No qualification claim or automatic lock action is emitted.
