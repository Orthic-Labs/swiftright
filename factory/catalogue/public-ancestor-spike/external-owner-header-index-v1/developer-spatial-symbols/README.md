# External owner header index v1

This folder contains one exact SourceKit `source.request.indexsource` capture per pinned SDK interface: DeveloperToolsSupport (`Preview`, `PreviewTrait`), Spatial (`Size3D` imported C identity), Symbols (`WiggleSymbolEffect`), & CoreFoundation (`CGFloat`). Driver flags came from each interface, target variants were removed, frontend-only flags were forwarded through `-Xfrontend`, & production target is `arm64-apple-macosx27.0`.

Outputs are raw facts only. `effectiveAccess` is copied only when emitted by SourceKit; no eligibility/public-ancestor conclusion is made. Spatial `Size3D` has no Swift declaration record in index; evidence preserves all 173 exact `c:@UA@SPSize3D` reference occurrences plus related C header receipt.

`attempts/failed/` retains one rejected CoreFoundation preimage & its exact exit-1 output. Successful raw outputs are under `raw/`, request bytes under `requests/`, stderr/process receipts under `receipts/`, & immutable source/tool copies under `archive/`.
