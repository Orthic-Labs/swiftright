# Flexible maximum-frame layout

`01-frame-maximum-convenience.patch` adds separate flexible-frame layout for `frame(minWidth:maxWidth:alignment:)` & `frame(minHeight:maxHeight:alignment:)`. Child proposals clamp finite parent proposals to normalized bounds; reported frames expand to finite offers, clamp to maximums, & use child intrinsic size when axis proposal is unspecified. Alignment positions child inside resolved frame. Existing fixed-frame layout stays unchanged. Finite main-axis maximums constrain wrapped spacers during stack distribution; infinite maximums preserve main-axis spacer flexibility & configured minima; cross-axis bounds preserve main-axis spacer behavior.

Malformed bounds are normalized for finite headless geometry: negative/NaN minima become zero, NaN maxima become zero, positive infinity remains unbounded, & maxima below minima are raised to minima. This normalization does not assert SDK behavior for invalid inputs. `idealWidth`/`idealHeight` overloads are outside scope.

Patch base: `e2875c5f`. Validation on exact-base private copy: `swift test` passed 167 tests, 0 failures (153 baseline + 14 focused tests). Added tests cover legacy frame calls, finite & infinite offers, intrinsic sizing, proposal clamping, alignment, Spacer constraints & bare-spacer behavior, same-identity invalidation, malformed-input finite geometry, & horizontal ScrollView witness. No native SwiftUI parity capture was performed.

Private scratch: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/scroll-extra/fresh-runtime-e287/probes/sr0-s/fresh-runtime`.
