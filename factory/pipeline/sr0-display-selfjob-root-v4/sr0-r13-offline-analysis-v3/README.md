# r13 same-host provenance adapter v3

This packet joins existing strict Windows r13 report, v2 materializer receipt, genuine v9 incremental receipt, release metadata, & compiled source manifest. It emits one bounded JSON provenance record; it does not rerun analyzer, read broad trees, mutate raw evidence, or claim qualification.

Root runs explicitly:

```sh
python3 -I factory/pipeline/sr0-display-selfjob-root-v4/sr0-r13-offline-analysis-v3/provenance_adapter_v3.py \
  --strict-report factory/pipeline/sr0-display-selfjob-root-v4/sr0-r13-offline-analysis-v2/strict-report-r1/report.json \
  --materializer-receipt factory/pipeline/sr0-display-selfjob-root-v4/sr0-r13-offline-analysis-v2/materializer-receipt-r1.json \
  --incremental qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/incremental.json \
  --release-build-metadata qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/release-build-metadata-v6-r1.json \
  --compiled-source-manifest qualification/tuple12-takeover/root-process-validation-v9/observed-incremental-v9-r1/compiled-source-manifest.json \
  --out .factory-work/sr0-r13-offline-analysis-v3/provenance.json
```

Known strict facts are preserved: 3,601 PresentMon rows, 47 displayed, 3,554 replaced, presentation p95 `3999.415 ms`, input-to-visible p95 `3044.3844 ms`, & W7 missing only because v2 materializer did not copy incremental input. Genuine v9 incremental receipt joins source manifest `26705e8f…`, source file `6e0f6ffb…`, WorkloadWin `7e749248…`, & renderer `7578cd5d…`; receipt remains `artifact_restoration_only`.

Display hold remains genuine. Strict report says minimized, occluded, or throttled; next capture needs isolated interactive full-visible context with foreground steal excluded. No threshold, raw row, or qualification rule is changed.
