Original `Image(systemName: "star.fill")` now has one usable Windows native observation, paired with existing Mac reference. Both render at 800×600; witness SHA is `0862162052b143a52e3f556e41f70fa02612b0b3f6ee83d7f7aecd835f6a018b`.

Actual Mac star points up; actual Windows star points down. Windows provider's row reversal is incorrect for this observed GDI glyph. Previous source-only orientation conclusion was wrong. Windows chosen face is `Segoe Fluent Icons`, glyph E735; it remains a declared substitute, not verified Apple-symbol parity.

`original-image-comparison-r1.json` records 2,298 different pixels without masks, scaling or normalization. Mac content bounds are `[0,1,79,76]`; Windows bounds `[0,5,80,75]`. Original host positions this case at top left on both sides. Fix orientation & fit in host provider, then capture fresh EXE. Do not repeat this known failing version twenty times.

Native coordinator completed, owned process exited with kernel proof, raw streams sealed & desktop lock released. Byte archive includes original provider sources, requested case, DLL/EXE joins, PrintWindow pixels & native logs. No golden promotion.
