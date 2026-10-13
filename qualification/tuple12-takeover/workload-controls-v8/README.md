# Tuple12 workload controls v8

Immutable successor over v7. It writes analyzer-required `presentmon.console.txt` after bounded PresentMon stream drains & passes `Base\incremental.json` explicitly to analysis. It preserves v7 artifact hashes, lifecycle gates, no-activate path, signed/raw exit checks, session absence, strict three-run semantics, & release/incremental refusal gates.

Source-only status: pending root parser/typecheck/native run. No receipt is qualified by this source packet.
