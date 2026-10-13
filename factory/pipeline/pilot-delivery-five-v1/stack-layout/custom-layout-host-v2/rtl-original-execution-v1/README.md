# Custom Layout RTL source case v1

Source-only RTL axis packet derived from original v7 Custom Layout witness. Inputs are child-count 2, proposal-width 48 DIP, layout-direction rightToLeft; child frames remain 12x10 & 16x14 DIP, yielding 30x25 & 40x35 physical pixels at scale 2.5.

Original v7 witness bytes are preserved as base SHA `sha256:afe77cdfbd5c73943aeebe52c515f2149c7951a4e3512f1678cda6625cdb58f7`. New RTL witness SHA is `sha256:3d971da04f4b5df0f2f0c65c6067d306fea727547d929307072f8be310c7817a`; only environment direction changes. Mac Count1 capture & Windows Count1 capture remain pending root supervision; no parity is claimed. Mac prep/build use fresh internal cache `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-rtl-original-v1`, never `/Volumes/D`.

Recipe axis source: `factory/recipes/data/swiftui.custom-layout.json` declares `layout-direction` values `leftToRight` & `rightToLeft`.
