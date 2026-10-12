# Immutable input cache proposal

`immutable-input-cache.ps1` is additive source for repeated Windows preflight reads. Caller supplies explicit measured whitelist rows `{Path,Sha256,Bytes}`. Cache admits at most 512 regular non-reparse files & 1 GiB distinct bytes. Each file opens with `FileShare.Read`, hashes through 128 KiB chunks, compares bytes/hash while lease remains open, and exposes `Get-ImmutableInputHash` with `Get-FileHash`-compatible fields. No ambient `Get-FileHash` override exists.

Only whitelist inputs cache. Outputs, observations, child receipts, and any unlisted path use `Get-UncachedOutputHash`, which opens, streams, & rehashes on every call. Caller closes cache in `finally` after child cleanup; close receipt records lease count & total bytes. Write/delete attempts against leased inputs must fail. Reparse path components reject before open.

Integration shape:

```powershell
$cache = New-ImmutableInputCache @($sourceRows)
try { $planHash = (Get-ImmutableInputHash $cache $planPath).Hash; & $preflightUsingCachedRows }
finally { Close-ImmutableInputCache $cache | Out-Null }
```

`$sourceRows` must be exact measured rows from current source manifest, never a directory enumeration. Keep output/observation/receipt paths on uncached hash path.

Root may stage helper beside fresh preflight source, replace repeated `Get-FileHash` calls only for exact whitelist paths, and retain existing output hash calls. Cache keys must derive from same measured path strings used by current source manifest; no broad directory discovery. Existing 30s renderer & 15s child deadlines remain unchanged.

`test-immutable-input-cache-controls.ps1` defines bounded positive/fault controls for baseline admission, wrong hash, write blocking under lease, changed unlisted output rehash, & reparse rejection. It leaves control files retained under supplied ignored `ControlRoot`; root runs it through `factory/tools/supervise-job.py`.
