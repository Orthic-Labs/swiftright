# Continuous shape RGBA adapter

Prospective shape-only adapter. It consumes `ContinuousRoundedRasterizer` output & existing `Bridge.registerImage`/`.image` ABI 0.6 transport. It has no fixture pixels, witness constants, renderer changes, or generic Image-provider code. Caller supplies resolved RGBA colors & physical geometry, retains returned `ImageHandle` while primitive is live, then releases handle on node removal.

Adapter expands registered canvas by full stroke width & shifts primitive origin by half stroke width. This preserves centered `.stroke` bounds around original path; current inset rasterizer therefore supplies transparent outer padding instead of `strokeBorder` geometry. Canvas dimensions are bounded integer physical pixels via upward rounding.

`package/source-manifest.json` binds adapter inputs to unchanged original witness SHA `73235389c2f255b5ceea4184a356fbf0e582d91e00a6ad9887da8de68c2773c7`, current v5-derived case SHA `26dab4867398bae5f1e9992a701f82e260fcd85a3649d790e8b984648039fd88`, & packet plan SHA `e4a28fafc615d642c924bb93ca5370cd0de220c1b115c82a3748d8c3aca58a72`. Runtime tree & receipt hashes bind current canonical runtime API rounded r1; compile source path is pinned directly to that staged package.

Geometry support is bounded to ordinary radii independently observed in R1/R2. Requests above `min(width,height)/(2*1.528664946556)` throw `unsupportedRadiusExtent` (rasterizer applies bound after its centered-stroke inset); R2 shows Apple adjusts large-radius controls after independently clamping extent, so adapter does not emit unverified geometry. Zero radius emits a five-element rectangle path.

This packet has no compile/native receipt. Integrate into fresh Rounded host source after runtime additive files are staged; preserve existing observation packets.
