# Toggle style metadata API

Base: runtime at `a1ec1fe3acbfb01a670f46ffa57255acab25f88b`. Apply `01-toggle-style-metadata.patch` to repository root.

Patch adds marker `ToggleStyle`, `DefaultToggleStyle.automatic`, `SwitchToggleStyle.switch`, & `View.toggleStyle(_:)`. Selected style type is recorded on resolved Toggle metadata only. Toggle layout, accessibility, value handling, & rendering remain unchanged; native style behavior is not claimed.

Validation: full suite 152 tests, 0 failures (150 at base plus 2 new tests). `PrimaryToggleStyleWitness.swift` uses unchanged pilot witness body (SHA-256 `f23c0daada461f9711c079fd54ccb7006e23700d6d299c0b1dd21463fbc21f1b`). Private build used `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/toggle-style-verify/probes/sr0-s/fresh-runtime`.
