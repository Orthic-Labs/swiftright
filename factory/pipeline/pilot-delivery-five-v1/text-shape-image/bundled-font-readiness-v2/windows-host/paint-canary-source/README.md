# Tinos paint canary source packet

This packet is a source-only opt-in canary for renderer font selection. It keeps
existing `windows-host/package/` immutable. Apply `paint-canary.patch` to a
fresh copied package before root-owned bounded compile/capture.

Canary witness paints identical `Aa@#` text twice: registered
`Font.custom("Tinos-Regular", size: 18)` beside explicit system serif
`Font.system(size: 18, weight: .regular, design: .serif)`. Host measures custom
run through exact Tinos resource adapter & control run through `Times New Roman`,
then logs separate retained runs. Root must join both paint logs with native
screenshot crops & require differing glyph pixels in expected crop pair before
claiming renderer selection. Registration, family lookup, metadata, or unequal
measurements alone do not prove glyph provider.

Root invocation adds `--paint-canary` to existing Tinos launch args. Required
logs are `FACTORY_TINOS_PAINT_CANARY_MEASURE`,
`FACTORY_TINOS_PAINT_CANARY_RUN`, & `FACTORY_TINOS_PAINT_CANARY enabled`.
Packet remains observational until root records source, native paint, screenshot,
& UIA joins.
