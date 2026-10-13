# SR1 shape/image/text host source packet

Scope: Rectangle/RoundedRectangle fill+stroke, Image(systemName: `star.fill`), & Text bundled-font host paths. Proposal packet only; root owns source integration, compile, native capture, archive, & Git.

Evidence-bound causes:

- Rectangle `Color.red` Windows bytes were `[255,59,48,255]` from `system.red = 0xff3b30ff`; paired Mac bytes were `[255,56,60,255]`. `0xff383cff` is a source proposal requiring fresh native receipt; it is not verified.
- Text paired report records Mac `Aa` at `28.0 x 28.0` DIP; Windows UIA records `28.0 x 28.8` DIP at scale `2.5`. Existing Text host passes `lineHeight: 29`, producing `72 px / 2.5 = 28.8`. This identifies host request/bridge font-metrics ownership; changing `29` to `28` is a recipe diagnostic candidate, not broad implementation. Native font metrics must be measured from provider-owned output before any shared host change.
- Additive host has a policy path for Image: `star.fill` selects Segoe Fluent Icons `FavoriteStarFill` glyph `E735`; named images require adjacent `FactoryImageAssets.json` with bounded RGBA bytes. No same-source Mac/Windows measurements exist, so provider equivalence remains held.
- Additive host has an explicit rounded-font guard: `.rounded` requires `C:\Windows\Fonts\ARLRDBD.TTF`; missing provider throws `FactoryRoundedFontProviderUnavailable`, & custom/private metadata throws `FactoryABIPrivateFontCollectionUnavailable`. No font receipt proves bundled-font parity, so this remains held.

Files:

- `host-source-fixes/FactoryFill.swift`: proposed semantic red mapping.
- `host-source-fixes/text-default-line-height.patch`: diagnostic candidate for exact Text host only; do not generalize.
- `host-source-fixes/renderer-red.patch`: proposed common additive template palette correction.
- `verification-packet.json`: source refs, expected channels, & holds.

Root commands:

```text
Review source proposals against fresh host/provider source.
Do not apply Text line-height candidate as shared font implementation until native provider metrics are owned & measured.
Recompute exact source manifest rows after any accepted edit.
Compile each fresh host with existing bounded Windows recipe, then run existing reader/admission controls & native capture flow.
```

Required channels: compile receipt, source bindings, runtime receipt/tree, renderer identity, Windows reader admission, native UIA, PrintWindow, screen repeat, foreground/ownership, cleanup, & raw streams. Native parity remains held until root closes existing platform gates.
