# Font metadata storage isolation

Patch `01-font-storage.patch` is based on runtime commit `bbceb5a14cab2be125af68f8e84014a29f3277a7` (see `BASE`). Apply with `patch -p4` against an exact `probes/sr0-s/fresh-runtime` source copy.

`Font.Metadata` remains a public value struct. `Font` stores explicit metadata in a private immutable `Sendable` box, exposes unchanged read-only `metadata`, & uses synthesized optional storage equality/hash over value-based box contents. Legacy `Font(id:)` values retain nil storage, exact IDs & no box allocation.

Focused tests cover independently constructed equal metadata values & Set hashing, unequal metadata, legacy/explicit same-ID distinction, retained snapshot values, & legacy nil/cache behavior.

Validation ran on internal disk copy `/Users/adrdsouza/Library/Caches/SwiftRightFactory/runtime-additions/font-storage/exact-bbceb5a1/runtime`; no binary ran from `/Volumes/D`.

Full suite: 175 tests, 0 failures (171 base tests + 4 focused tests); arm64 `Font.stride` is 24 & `ResolvedStyle.stride` is 64.
