# Factory viewport proposal

Frozen r5 `FACTORY_RENDERER_READY` reports physical800×1396 at scale2.5; owned PrintWindow client is800×600. Staged ABI `swr_window_get_metrics` returns launch-time WIN_W/H values; staged `view.rs` stores those once. New factory helper reads actual owned HWND instead of changing renderer/ABI.

`FactoryViewport.swift` enumerates current UI-thread windows, requires exactly one title `Alchemist FactoryProbe` belonging to current PID/thread, then pins HWND. It validates nonzero bounded physical GetClientRect dimensions & DPI48…768; scale=DPI/96, logical proposal=physical/scale. Any owned foreground PID aborts before/after read; helper never activates/focuses/moves windows. DPI drift aborts because Graph scale remains immutable.

`RendererHostViewport.swift.in` preserves witness & existing primitive lowerer. Initial owned metrics populate Graph proposal; stale ABI metrics remain separately logged. Every tick rechecks same HWND/PID/thread & updates viewport/rootProposal before Graph.flush. Graph layout caches use ProposedViewSize keys; changed logical proposal selects new cache entries & flush always relays out. Graph & State remain intact. Native DPI drift never rebuilds Graph or relabels old pixels.

`prepare_viewport.py` creates NEW package lineage with both Swift files/source bindings. Prior helpers, 10 initial67 compile receipts & r5 archives stay frozen. Proposal needs exact source/unit review before any new UI launch. Synthetic unit fixtures count zero native captures.
