# F1 compiler edge spike

Review-only evidence for seven held F1v7 cases. Frozen link input is `factory/catalogue/compiler-cursor-spike/link-evidence.json` with SHA-256 `836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`.

Five SwiftUI projected properties are active under `compiler(>=5.3) && $TildeSendable`. SourceKit emits two parsed-identical declaration records per row, same USR, line, name, context, kind, & access. Production cardinality gate rejects them; they remain held.

`SwiftUICore._ImpossibleActor` is actor source line 18132, while SourceKit emits `source.lang.swift.decl.class`. A pinned fixture proves same toolchain behavior for actor source, & ordinary class control proves mangled `Class` alone cannot distinguish kinds. Callable `actor_bridge_validator.py` accepts one exact raw card only after source-byte hash, actor marker, line/name/context/access/module, & demangled USR module/name/tree checks. Nonvacuous controls cover changed source bytes, wrong USR/tree/module/name, duplicated target sections/children, wrong line/name/context/access/source hash/source marker/module/class marker, & duplicate raw cardinality. Archived `probe-receipts.json` records actual SourceKit, swiftc, swift-demangle, & branch probe invocations plus tool/output hashes. Review proposal remains unpromoted; no adapter changed.

`WidgetBundleBuilder.buildLimitedAvailability` line 28491 is inactive `#else` because compiler selects `$InlineAlways`. Indexsource has zero entity, cursor returns `Unable to resolve cursor info.`, & symbol graph has two signature-ambiguous overloads. It remains held.

Run:

```sh
python3 factory/catalogue/compiler-edge-spike/investigate_edges.py
python3 factory/catalogue/compiler-edge-spike/test_edge_evidence.py
```

Only files in this directory are created. Existing evidence, adapters, & catalogue are untouched.
