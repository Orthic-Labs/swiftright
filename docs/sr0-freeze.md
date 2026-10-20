# SR0 freeze: ABI 0.6 on tuple 13 (20 October 2026)

Adrian, 20 Oct, when asked whether to freeze: "why would we not freeze it if it's qualified?" Recorded as the freeze decision (#22).

Frozen reference build = `qualification/tuple13-candidate.json` (status QUALIFIED), qualification run `probes/sr0-s/fresh-on-bridge/out/tuple13-qualification-run-r3/` (all stages PASS, exit 0), stage source `a9556b77f`, renderer source `91400f36e` (stage + TextCache byte budget, #34).

| Member | sha256 |
|---|---|
| windows_renderer | `1aa8ad22171c07a61e24786e074185e8378c67089ea457a9577e5104dd4c1f07` |
| windows_fixture_exe | `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374` |
| windows_smoke_exe | `064e5d420ed5458f9069395284f4ce5e6af41c17c142ac7ba6346320d319b0ea` |
| old_msix | `5f77ccbbc0761ca4d4a4c1a760d2e070e26421412f069baa968a234b7ab203c2` |
| new_msix | `478b3bebf26da74b4817f7f19a12c288e8325c12019ba1c0b917651a907e6c22` |
| old_dmg | `14d5874dcfd8782ddecf88916bd298824a0344a204fd2c5a179916736993a066` |
| new_dmg | `cc8bab86409a4ecf7ba52c6a5bb1ed3177683b39e235ed60019bf292badbc5fb` |

Known SR0 limits carried into the freeze (recorded, not hidden):
- Narrator spoken output not yet listened to by a person (#23); automated provider checks pass.
- IME candidate list does not follow a layout move (SR1, #33).
- Selection highlight and caret after launch focus: painted (WGC, 20 Oct, #25); only the highlight colour differs from the Mac (SR1 parity).

From here: ABI 0.6 and the tuple 13 members do not change; product work continues on master under SR1 and later stages. Git tag `sr0-freeze-abi-0.6` marks the commit holding this record.
