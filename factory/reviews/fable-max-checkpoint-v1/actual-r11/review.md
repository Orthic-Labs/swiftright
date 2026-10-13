**Verdict: at-risk.** Continue the build-capture-compare loop, materially change where fixes land, and stop guard and plan-metadata work. R10's next steps were done: sixteen Custom captures compared offline, first native Image pair captured, closed-callback guard written. Two misdirections remain. Every Windows paint decision for these blocks still lives in per-witness FactoryProbe sources rather than in SwiftRight, and Image is held to a bar its own code forbids.

**Verified facts.** Image identity joins hold: the Mac manifest's witness and PNG hashes match the comparison receipt, and the exit certificate binds EXE 44824c… with natural exit 0 and sealed streams. I confirmed orientation from the receipt's own numbers. Mac centroid y 41.5 sits three pixels below its bbox centre, an upright star; Windows centroid 35.9 sits four pixels above its bbox centre, inverted. Cause is the row reversal at `FactorySystemImageProvider.swift:117`; GGO_GRAY8 buffers are top-down. Root under-states a second defect: the glyph is cropped, not fitted. Font height 80 yields an 80×78 black box centred into an 80×70 target with overflow rows skipped at lines 112 to 120. Windows content is exactly 70 rows; Mac is 75 rows inside the witness's 32-point scaledToFit frame. Un-flipping alone leaves the height wrong; the 80×70 target implies the runtime's declared aspect differs from Apple's.

Custom Layout runs 1 to 7 are zero-diff with identical content bounds in `offline-sixteen-comparison-r1.json:14-27`. Run 17 prints `FactoryOwnedRendererHWNDAmbiguous` only after bridge-run-return, so the log cannot show whether ambiguity preceded or followed the close. The v7 guard fixes late-callback ordering only; one failure in seventeen fits equally a second top-level window appearing before close.

Stack v8 wires the message-font policy with correct DPI arithmetic: 12 DIP at DPI 240 versus Mac's 13-point body, replacing a hardcoded 16. Neither is a recorded product decision. Prefix churn is self-inflicted: prebuild receipts emit prefixed hashes, comparisons bare hex.

**Implementation versus machinery.** Real: the Custom Layout runtime path with sixteen exact pairs, and the first Image raster. Machinery: prefix guards, the r4 to r5 plan-hash cycle, v7 to v8 font policy, bundled-font transport repairs. Image provider, fill mapper, colour resolution and body font exist only inside FactoryProbe, not SwiftRight.

| Block | State |
|---|---|
| Custom Layout | Working, verified for one LTR two-child case; run-17 is host lifecycle, cause unproven |
| Image star.fill | Builds, renders, inverted and cropped; provider is probe-local; line 55 rejects any parity label except unverified |
| ZStack/overlay | Layout working; 307 px all inside the text run; font churn cannot change that |
| Shapes fill/stroke | No evidence in packet; stroke regression status unknown |
| Bundled-font Text | Not delivered; renderer cannot load the font without a protected change |

**Strongest counterargument.** Identity joins caught the R8 witness mismatch, stale receipt reuse and the stale plan hash. But each was an error the pipeline manufactured. The product errors, flip, crop and HWND race, were found by reading pixels and logs. More guards will not find the next one.

**Corrective actions**
1. **Image.** Delete the flip, scale the raster into the target preserving aspect, check the registry's intrinsic aspect against Mac's 79×75, capture once, compare bounds within one pixel, centroid sign and tint. State acceptance now: SF glyphs cannot ship on Windows, so a declared provider with matched metrics and orientation is the product, not a diagnostic. Move the provider into the runtime as an additive Windows API.
2. **Custom Layout.** Declare case one working and verified. Run v7 at count five, print the error at fail time with the tick clock, then run an RTL case. No further plan-metadata cycles.
3. **Fonts.** Decide Font.body on Windows once, in the runtime, and compare Stack's non-text pixels exactly. GDI private registration is invisible to DirectWrite, so name the single renderer change bundled text needs and put that scoped request to Adrian instead of more lineLimit host variants.

**Genuine holds.** The renderer and ABI boundary while SR0 is OPEN is user-recorded; it blocks only continuous corners and private-font loading. Not holds: quota review debt, paired-20 before implementation, the Image never-counts rule, HWND ambiguity pausing Custom Layout, further guard work. Possibly stale: continuous corners could be CPU-rasterised through the ABI 0.6 RGBA registration the image provider already uses; acceptability is Adrian's call.

**Unchecked.** Runs 8 to 16, stale plan-hash attribution, registry intrinsic size, Rectangle stroke, R8 continuous-default proof, Mac runs beyond 001. The Mac PNG is absent at its manifest path. I read 17 text files, one over the cap, and one PNG.

**Next action:** set `sourceRow = row` at line 117, replace centre-and-clip with aspect-preserving scaling, rebuild v9 once, capture once, report bounds, centroid sign and tint against Mac.
