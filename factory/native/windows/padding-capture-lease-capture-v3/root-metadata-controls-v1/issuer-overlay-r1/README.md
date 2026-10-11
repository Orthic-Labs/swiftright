# Prefixed issuer overlay r1

Source-only issuer overlay for fresh Count1 & Count20 reissue. Frozen `issue-before-launch.ps1` remains immutable & historical. `issue-before-launch-prefixed-r1.ps1` preserves preflight, source/host pins, exclusive writes, metadata shape, & no-native-before-issue ordering, while allocating `capture/<32 lowercase hex>` & `image/<32 lowercase hex>` IDs before launch.

Overlay files must be included in execution overlay refs; adapter producer/validator require exact issuer filename plus four frozen Count1 r3 execution scripts. Root retires prior GUID-only metadata before invoking overlay. Offline controls validate actual `common.schema.json` ID rule plus 20-row cardinality, run sequence, uniqueness, wrong prefix, bare GUID, duplicate, & short allocation faults.

```text
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/test-issuer-guid-controls.py
```
