# Rectangle host fix v2 — prospective centered root adapter

Windows paired evidence placed exact 40x20 Rectangle at `[0,0]`; Mac paired
evidence placed it at `[140,110]` in 320x240 DIP viewport. This packet preserves
exact original witness & recipe. `FactoryCenteredLayout.swift` is factory-owned
host math: direct root Rectangle child receives centered bounds; nested children,
other primitive kinds, & non-fitting bounds remain unchanged. It does not alter
runtime, renderer, ABI, or historical plans.

Apply `factoryCenteredRootChild` in fresh Windows host `walk` immediately after
reading `n.pixelFrame`, passing `directChildOfRoot: n.kind == "Rectangle" && parent == UInt64(root.instance + 1)`
using host's existing `root` node identity. If host walk cannot prove direct root
identity, fail closed instead of centering arbitrary nodes. Keep viewport from
owned `GetClientRect`, fixed 320x240 initial witness, & existing fill color
adapter. Root owns fresh bounded compile/capture; no prior EXE, receipt, or parity
hash can be reused.

Expected fresh native geometry after root capture: x=140, y=110, width=40,
height=20 at 1x equivalent viewport. This value is a placement target, not a
measured result from this source packet.
