# Seed compiler-origin source admission v8

V8 prepares five remaining seeded Mac cases for future bounded capture. V7 was held because `case-root` contained recipes/manifests but no canonical full case JSON matching each manifest case hash. V8 archives exact canonical full gate cases under `inputs/` & binds each raw byte hash to its manifest.

Rows: `swiftui.disabled`, `swiftui.image`, `swiftui.shapes.fill-stroke`, `swiftui.text.bundled-font`, & `swiftui.toggle`; seed `14577611000270672472`. V6 bounded compiler/AX observer source remains byte-pinned through `admission/v6-admission-pins.json`; runtime dependency archive contains 23 pinned files. `text.bundled-font` remains held for bundled-font observability. No capture, GUI action, Accessibility request, or permission request ran; `captureStatus` remains `NOT_RUN`.

Planned collector command uses exact v8 case root:

```sh
/Volumes/D/claude/swiftright/factory/.venv/bin/python /Volumes/D/claude/swiftright/factory/oracle/mac/seed-origin-v8/capture_origin.py --manifest <each v8 inputs manifest> --case-root /Volumes/D/claude/swiftright/factory/oracle/mac/seed-origin-v8/inputs --scratch /Volumes/D/claude/swiftright/factory/oracle/mac/seed-origin-v8-capture-20261011 --output /Volumes/D/claude/swiftright/factory/native/macos/evidence/seed-origin-v8-capture-20261011 --runs 20
```

Replay source admission:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/oracle/mac/seed-origin-v8/verify_v8.py factory/oracle/mac/seed-origin-v8 --workspace /Volumes/D/claude/swiftright
PYTHONDONTWRITEBYTECODE=1 python3 factory/oracle/mac/seed-origin-v8/test_v8.py
```

Thirteen controls reject source, pin, witness, duplicate identity, recipe, dependency, collector, permission, missing canonical case, rebound canonical case, canonical hash/id, & stale case-root faults.
