# Font metadata storage evidence

Base: `bbceb5a14cab2be125af68f8e84014a29f3277a7`

Private exact-base copy: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/runtime-additions/font-storage/exact-bbceb5a1/base`

Private patched copy: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/runtime-additions/font-storage/exact-bbceb5a1/runtime`

Patch uses integration paths `probes/sr0-s/fresh-runtime/...`; `patch --dry-run -p4` passed against exact private base.

Validation:

- full suite: 175 tests, 0 failures; 171 base tests remain green, 4 focused tests added
- focused FontAdditionTests: 10 tests, 0 failures
- arm64 `Font.stride`: 24; `ResolvedStyle.stride`: 64
- stdout: [full-test.stdout](full-test.stdout)

Focused cases cover equal metadata value equality & Set hashing, unequal metadata, legacy nil storage/cache behavior, & retained snapshot metadata.

SHA-256 receipts:

| Item | SHA-256 |
|---|---|
| BASE | `6eb41fc377037a6748a22a1b1b49286b45bb8a77df4cbebbd0b419cb4f4fc01b` |
| 01-font-storage.patch | `059ec4489cf0e543eb892c685a1bfb95ffdb9097f55e59732385fae852e30050` |
| full-test.stdout | `c20d043379774e566bbb3aedcc62e2fcc8ca94c9ae5a5b71583612f237d0c6ac` |
| base Controls.swift | `154ab349766ab3d555eba5570e9b00b65da7f523a005cea74f205473c29a22ee` |
| patched Controls.swift | `646f42253fb783e10c02c37210bb936a9c3dda5b7347a0ed18a24c213732e4d1` |
| base FontAdditionTests.swift | `215556e40b31454530388ed8c500ecd4d2c8ab286d75500cce530fdf02576b9d` |
| patched FontAdditionTests.swift | `8200ad8a7b4ae3ef047fbda26f929971655e6f20ca91c8634eb4fb3a220e6552` |
| source receipt | `3c47efc29c53d31cf09dd6f8767fecf1b6ccbb66b47673befa105b477226eca9` |
