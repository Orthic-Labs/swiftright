# SR0 supplemental release v1

`validate-release-evidence-v1.py` is release-only evidence validation for v5
Windows runs where display/parser qualification failed after owned processes
reached terminal state. It reads bounded receipt JSON, computes owner-CAS
eligibility from retained original-handle terminal proofs, sealed streams,
absent PresentMon session, workload exit 0, & self-only 1 GiB job state. It
never mutates lock, never reclassifies qualification, & never claims display
success. `test-release-evidence-controls-v1.py` mutates in-memory receipt
fields then calls same production `evaluate()` function.

Observed v5-r6 facts bound into current staging review:

- collector PM forced-owned exit is raw `4294967295`, signed `-1`, stop exit `0`;
- PM session absent, PM streams sealed, PM stderr is 65-byte benign warning;
- workload original handle terminal, exit raw/signed `0`;
- collector active-after `1`, self-only `true`, peak `506167296`, limit `1073741824`, flags `512`;
- launcher descendants quiesced & self-only; observer schedule/worker original handles terminal;
- CSV/parser proof remains failed due ProcessID mismatch; release output must stay `qualification=blocked`.

Root-owned invocation after extracting exact collector, launcher, & observer
receipt JSON objects from archived v5-r6 transport evidence:

    py -3 factory/pipeline/sr0-display-selfjob-v4/supplemental-release-v1/test-release-evidence-controls-v1.py --collector <collector-receipt.json> --launcher <launcher-receipt.json> --observer <observer-receipt.json> --output <fresh-controls.json>
    py -3 factory/pipeline/sr0-display-selfjob-v4/supplemental-release-v1/validate-release-evidence-v1.py --collector <collector-receipt.json> --launcher <launcher-receipt.json> --observer <observer-receipt.json> --output <fresh-release.json>

Expected status is `release-eligible-held` only when all ownership checks pass;
`lockReleaseDecision` then reads `owner-cas-eligible-release-only`, while
`qualificationClaim` remains false & `lockMutationPerformed` remains false.
