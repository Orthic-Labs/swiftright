# Seeded compiler builder v2

Source-only adaptation of reviewed scroll-build-v4 retained-handle builder for five frozen seeded plans: custom-layout, padding-frame, preference-key, scroll-view & stack-overlay. Old seeded builder remains unchanged.

Run `run-controls.ps1` once in fresh builder directory using Windows PowerShell 5.1. It generates cleanup, host-input, AST, strict integer & reserved-assignment controls, invokes actual production admission, preserves seven mutated fixtures, then validates invocation proof. Builder refuses missing/stale/failed controls before starting compiler.

Run `build-hosts-v2.ps1 -Package <exact allowed package>` serially after controls pass. Each package requires fresh `build-v2-r1`. Exact reviewed plans bind host/runtime/bridge/compiler/renderer bytes & metadata; inputs are checked before compilation & after successful exit. Retained kernel handle owns root compiler termination; natural exit receives no kill. Deadline is 300 seconds; raw stream drains & receipt are retained. Timeout leaves descendant ownership unresolved & aborts further builds pending resolution. No executable is launched.

Prepared controls are unrun in this packet; source review provides no compiler/native qualification.
