# F1 duplicate identity spike

Review-only evidence for five SwiftUI projected-property rows held by frozen link evidence SHA-256 `836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`: `$isOn` 4080, `$isExpanded` 5533, `$document` 9717, `$document` 23750, `$selection` 32822.

`archive_duplicate_receipts.py` reruns exact pinned SourceKit request headlessly, archives fresh output whose SHA equals frozen response `352c81a020cd442aea487f0d74998f29b27d550b6958fd35582e4e14b3c1ef34`, extracts complete declaration object bytes, runs `swift-demangle --expand`, & compiles a `$TildeSendable` branch probe. Each row proves two records, exact raw-byte equality, parsed-field equality, one exact source line, active branch, enclosing scope, shared USR, & USR tree identity.

`duplicate_identity_validator.py` & `duplicate-evidence.json` retain unqualified historical work. Independent review found stale column, argument & scope mutations accepted by that guard. Its parser/digest helpers remain pinned inputs to replacement proof; its old validation function supplies no authority. No promotion or global deduplication exemption is made.

Historical reproduction:

```sh
python3 factory/catalogue/duplicate-identity-spike/archive_duplicate_receipts.py
python3 factory/catalogue/duplicate-identity-spike/investigate_duplicates.py
python3 factory/catalogue/duplicate-identity-spike/test_duplicate_identity.py
```

## Independent exact identity candidate (review only)

`exact_identity_candidate.py` is additive replacement proof for five frozen rows.
It reads original `836e763c…` link evidence, reconstructs complete actual raw response,
checks exact byte intervals/blocks/entities, binds actual source/request/tool bytes,
reconstructs SDK brace owners & conditional arms, then checks complete fresh USR
output plus exact nominal owner tree. Only two identical emissions of one unique
active source declaration qualify. Original evidence & validator remain history.
Independent review cleared five exact identities after whole-artifact replay & 120 required-reason fault controls. Reviewed consumers may use these five identities; golden promotions remain 0.

Reproduce fresh compiler/demangle receipts, then run paired fault controls &
whole artifact equality replay:

```sh
python3 factory/catalogue/duplicate-identity-spike/capture_exact_probes.py
python3 factory/catalogue/duplicate-identity-spike/test_exact_identity_candidate.py
```

Fresh probe binaries use internal Mac temporary directories & are removed after
capture. Review artifact: `exact-identity-candidate.json`.
