# Adapter v9 r14 binding review

Reviewed source plan:

- `fresh-count20-adapter-plan-v1.json`: SHA256 `6fa3d83e9ccac74abafd3b9c9ee1226bcd604b06b7aab5be358dfc10f13449b4`, 3146 bytes.
- r14 issued metadata: `windows-root-headless-r11-r1/observed-headless-v14-r2/coordinator-r1/issued-metadata.json`, SHA256 `d8ac2784cce18a01e2f937503022aaa42414744e48a389abc9b507bd7d5a8b7c`, 29313 bytes.

Tuple ID, case ID/hash, source hash, Mac host hash, Windows host hash, expected count 20, prefixed capture/image patterns, & `frozenTupleBound=false` match between plan & r14 issued metadata plus its referenced candidate tuple. Issued metadata run ID is `4c135fd2a703495ba50191ebdc5005ae`; its 20 IDs are actual r14 values from v14 issuer.

Hold: plan has no runID field, & current `produce-inputs-v9.py` validation checks issued expectedCount/sourceHash/frozen state but does not bind issued `runID` to plan or caller receipt. Strict fresh admission must carry this exact run ID through input-map/proof/reader joins. Synthetic fixture controls below intentionally use deterministic IDs & `nativeEvidence=false`; they cannot close this hold or qualify r11 output.
