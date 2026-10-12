# Text paired20 diagnostic source

`compare_text_paired20.py` consumes one explicit `factory-text-paired20-input-v1` adapter manifest. Adapter rows must reference measured Mac AX/compositor JSON, measured Windows UIA/PrintWindow JSON, exact PNG bytes, & canonical case/tuple/source/recipe documents. Every reference is stat-checked, symlink-rejected, streamed-hashed, & byte-bound before parsing.

Each row requires `contentViewportDip={width:120,height:48}` separately from compositor frame metrics & `titlebarPx=32`. Scalar PNG summaries retain dimensions, row digest, bounded color histogram, ink bounding box, & pixel count. Font metrics carry requested system/default/24/regular values; wrap metrics carry source text `Aa` & measured line count. Font, wrap, AX/UIA, viewport, clipping, & compositor values remain provider observations; report status is diagnostic with parity held.

`--controls` executes 16 mutations against real input references: case/tuple/source/recipe identity, ordered capture/image IDs, missing row, raw/metric/pixel hashes & bytes, content viewport, titlebar, & lineage. Every mutation must reject before any output claim. Controls are source-only; no native, GUI, compiler, lock, remote, or Git action.

Adapter fields are intentionally explicit. `metrics.rawRef` must equal its side's measured raw JSON ref & metrics identity must equal row canonical identity. This prevents fixture substitution while keeping raw archives immutable.
