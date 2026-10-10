# Snapshot shape storage isolation

`01-shape-storage.patch` is based on runtime commit `67b841fbbb5b8571a14390637bd875b62bf433ad`.
It stores optional `ResolvedShape` metadata in a fileprivate immutable box, exposing unchanged public read-only `shape` values. Legacy snapshots keep nil storage, so no shape box is allocated; shape snapshots allocate one box. Box equality compares shape values, preserving `ResolvedNode` value equality independent of box identity. `ResolvedNode` stride is 648 to 576 bytes on arm64; shape geometry, paint, public getter, `Equatable` & `Sendable` behavior remain unchanged.

Focused tests cover independent equal values, geometry & paint inequality, nil legacy snapshots & retained snapshot immutability. Full validation ran on exact source copy at `/Users/adrdsouza/Library/Caches/SwiftRightFactory/snapshot-storage/exact-67b841fb/runtime`; no binary ran from `/Volumes/D`.
