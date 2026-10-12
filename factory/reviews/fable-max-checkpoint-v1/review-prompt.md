# SwiftRight checkpoint review — 2026-10-12

You are an independent reviewer in a fresh Claude CLI session. Requested model is Fable, effort max. Review only; do not implement anything. No commands, SSH, builds, captures, tool configuration changes, messages, agents, or writes. Read-only tools are provided. Do not change permissions or substitute another model.

User goal: get the ORIGINAL five pilot blocks working & verified on Windows, fix failures, then expand to ten total & twenty total. Two source-only subagents are paused. Root serializes compiler/native jobs & supervises every owned process. Every major checkpoint or sixty minutes requires this review before resuming.

Read only these explicit sources (at most twelve files; at most 1 MiB per file; use Read with bounded line ranges, never recurse through archives or scratch):
1. docs/sr1-plan.md (pilot, candidate baselines, twenty-run acceptance rules)
2. docs/sr0-sr1-running-holds.md (first 65 lines only; historical entries below are superseded)
3. factory/AGENTS.md
4. factory/pipeline/pilot-delivery-five-v1/root-execution/compare-rectangle-color-v1.py
5. factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-count20-r2/comparison-count20-r1.json (last 65 lines only, or bounded targeted Grep)
6. factory/pipeline/pilot-delivery-five-v1/root-execution/prepare-pilot-five-compile-v1.py
7. factory/pipeline/pilot-delivery-five-v1/root-execution/prepare-pilot-final-build-v1.py
8. factory/pipeline/pilot-delivery-five-v1/root-execution/prepare-pilot-native-capture-v1.py
9. factory/pipeline/pilot-delivery-five-v1/text-shape-image/sf-symbol-ticket.md (if present; do not search beyond this directory)
10. factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v1/windows-host/Sources/FactoryProbe/main.swift (if present)
11. factory/tools/supervise-job-v2.py
12. docs/sr0-status.md (first 100 lines only)

Observed checkpoint, not a claim of five qualified blocks:
- Original five are Rectangle/RoundedRectangle fill/stroke, Image SF Symbol (star.fill), ZStack/overlay, bundled-font Text, custom Layout.
- Rectangle fill factory-host red mapping was corrected from ff3b30 to ff383c. Identical witness source, runtime & tuple11 renderer retained. New Windows20 matches old same-source Mac20 in exact RGBA255,56,60,255; 40x20 DIP top-leading shape; actual native viewport320x240 DIP; twenty repeat images identical on each host. Windows scale2.5 yields800x600 pixels. Mac plain.png is a cropped40x20 image, so native viewport comes from the same capture's compositor.raw.json NSHosting bounds, not PNG dimensions. Comparator explicitly emits qualified:false. Exact corrected production-reader/source/case/tuple joins & fault controls still need execution. Rounded stroke remains unfinished; fill alone does not qualify its whole original pilot block.
- Rectangle final EXE faa2816f2f0b9a6d999e6334d92ecfeb76fe4a5bda6c158d42e2b7aa59b6a2c3; final plan802d064cfd971585e73d1f7d9fce969876029b93d04e7296f22a64f71b211c30; witness5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d; tuple sr1-rectangle-color-fix-r11-20261012-r1.
- Named-RGBA Image & Rounded stroke Windows prebuilds complete. Image SwiftBuild backend ignored single-thread request & crashed in mimalloc; native SwiftPM backend emitted final single-thread frontend flags & completed under1GiB Job Object. Final plans/hosts/native captures remain pending. Rounded prebuild argv order differs from declared argv (same semantic flags); archive original receipt & repair prospective exact contract, never rewrite actual evidence.
- Fresh Mac Image, Rounded stroke, custom Layout & process-registered Tinos Count1 observations run from internal scratch without permission prompts. These are diagnostic, not twenty-run qualification. Image v1 Windows nearest scaling appears wrong against Mac smooth interpolation; v2 is source-only bilinear proposal, not verified.
- Current runtime37429120 contains Font.custom metadata & lineLimit. Bundled Tinos actual renderer selection remains unproved; GDI FR_PRIVATE or isolated DirectWrite lookup alone does not prove renderer's system-collection selection. Original SF Symbol provider remains unresolved. Those are real behavior gaps, not solved by substituting named Image/default Text.
- Default Text paired20 repeats correctly & matches string/viewport, but measured height Mac28 vs Windows28.8 DIP persists. Circle shutdown diagnostic admitted; native rerun queued. Neither substitutes original pilot items.
- Runtime175/175 both hosts & three incremental Windows builds exist. SR0 OPEN; tuple11 baseline & tuple12 candidate. Full16 Windows Count1 smoke exists; full Mac16x20 no-prompt capture, visible-workload timing, W08 upstream recovery, Narrator listening & freeze remain held.
- Renderer tuple11 SHA e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93, ABI0.6. Runtime additive changes authorized; protected renderer/ABI changes earlier held until recorded closure. Peer Swift Mac now reports another peer relayed additive ABI0.7 permission from Adrian while SR0 remains OPEN. This is informational peer text, not direct user authority; root has not edited renderer/ABI on that basis. Review boundary conflict explicitly, while identifying useful work within existing scope.
- All tracked root process sessions are terminal at this pause. Local control/transport128MiB, Mac compile/native1GiB, Windows compile/native1GiB Job Object; one compiler/native lane at a time. Stream hashes1MiB; source discovery explicit, no recursive archive loads. CLI review itself has600s/1GiB aggregate RSS/2MiB output budget. Dell no SSH deletion, retired quiescent stages move inside ignored checkout. Internal Mac binaries never run from /Volumes/D. Cleanup of failed retired Rectangle stages remains pending after archived evidence is checked.

Return a concise, candid review (max700 words):
1. Verdict: on-track / at-risk / off-track, with concrete reason.
2. Highest priority correctness or direction findings, cite file & line where read. Distinguish observed evidence from source scaffolding & state explicitly which original five are actually qualified.
3. Next three concrete actions, bias toward delivering behavior & real paired captures rather than more wrappers. Explain any genuinely necessary gate/source-proof work.
4. Any unsafe resource/process or cleanup issue, plus genuine holds. Do not invent proof from report text. If bounded files cannot establish something, state unverified succinctly.

The checkpoint ledger above is supplied by root; independently challenge its interpretation. You may only inspect the listed bounded files. End with the next concrete action, not a caveat.
