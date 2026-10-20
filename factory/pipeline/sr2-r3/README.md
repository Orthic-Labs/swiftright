# SR2 R3: springs (issue #38)

Five manual-clock cases built from the block 18 template (`blocks-6-10/swiftui.animation/default-spring-v1`). Each widens a bar from 100 to 250 pt and is checked with the block 18 clock gate at a 1 px extent tolerance.

- snappy-v1: `.snappy`.
- bouncy-v1: `.bouncy`, which overshoots.
- response-v1: `.spring(response: 0.4, dampingFraction: 0.7)`.
- duration-bounce-v1: `.spring(duration: 0.35, bounce: -0.3)`.
- delay-v1: `.snappy.delay(0.2)`.

Clock times avoid the 1/300 s step boundaries. Frames are sampled before the earliest removal and after both sides have settled, because SwiftUI's removal rule for parameterised springs is not modelled (`../sr2-r3-spike/SPIKE-RESULT.md`).
