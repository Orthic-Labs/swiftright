# Count1 adapter-input producer r3 / adapter v4

`produce-count1-inputs-r3.py` turns one explicit archived Count1 result map into frozen settled-adapter input JSON. Caller supplies every path in `input-map.json`; producer refuses discovery, fallback, overwrite, unsafe path, missing file, byte/hash drift, missing producer/profile/source/runtime/worker closure, missing r4/r5 overlay, or Count20 data.

```text
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/produce-count1-inputs-r3.py \
  --archive-root <archive-root> \
  --input-map <explicit-count1-input-map.json> \
  --output <fresh-inputs.json>
```

Map `roles` must name all 12 frozen adapter roles. `producerSource` must cover every `dependencies/producer-stage.json.files` row with matching bytes & SHA256. `source`, `runtimeModules`, `runs[*].workerSource`, `metadataRecordPaths`, & `executionOverlay` are exact caller-supplied closures. `runs` must contain one Count1 row with all 25 raw/receipt refs. `executionOverlay` must use exact `/execute-r5` root & list `coordinator-r5.ps1`, `interactive-task-r5.ps1`, `dispatch-r5.ps1`, `capture-repeat-r5.ps1`, & `integration-prefixed-ids-r1.ps1` with required SHA256 pins; frozen `/execute-r4` remains accepted only for archived failed source. Separate `issuerSource` must point to `issue-before-launch-prefixed-r1.ps1` under issuer-overlay-r1 with exact SHA256; each issued capture provenance producer must name this issuer. Frozen base producer profile remains separately sealed.

Output preserves actual recorded Windows metadata paths while all archive refs remain safe POSIX-relative refs with exact SHA256 & byte count. It records overlay provenance in `executionOverlay`; bounded adapter-v4 validates exact r5 files (with archived r4 contract retained), paths, hashes, & base profile before unchanged v3 normalization logic. Output remains observational (`qualified=false`, `nativeParity=hold`). No native, GUI, compiler, remote, lock, or signing action occurs.

Actual tuple source inputs can retain recorded Windows paths. Producer seals safe archive replacements in `tupleSource`; bounded `adapter-v4.py` validates those raw joins & overlay refs before running unchanged v3 normalization logic. Use `run-adapter-v4.py` after producer output; v3 remains available only when its original tuple refs are already safe.

Input map must be built only after root fetches actual Count1 output. No map or output may use synthetic fixtures, guessed filenames, post-hoc case relabeling, or historical template values.

Current producer profile v4 is `../dependencies/producer-stage-v4.json`, hash `sha256:72016fe5689e9cb74ef851ab6be2665f74b1b5a73ec0711e406046748b287967`, with 76 rows copied from actual installed Count1 transfer closure `sha256:0f0405fc0d7633cfff105942cbfffbbe7fe62cd404cc517c5264f5c21ad43f2a`. Stale v3 profile remains historical; unknown profile hashes fail closed.
