# Windows native factory lane

Immutable inputs: `D:\Claude\sr0-r09`, renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, runtime source `be9a922028079fb8a51c6bb47299dfb6e9965d06`.

`stage-inventory-20261010.json` binds live executable/dependency hashes, Swift toolchain, OS & sessions. `stage-exports-20261010.json` lists PE exports without DLL loading. `primary-typecheck-summary-20261010.json` binds actual primary cases to compiler diagnostics: disabled compiles; nine other primary witnesses fail against staged runtime APIs. Raw sources, manifests & diagnostics live under `primary-typecheck-20261010/`.

Prepare unchanged generated witness & new factory renderer host:

```sh
python3 -m factory.native.windows /absolute/generated.manifest.json --output factory/native/windows/fresh-package --renderer
```

Copy new package & scripts into corresponding Dell factory path; compile with `compile-probe.ps1 -Package <path>`. This writes scratch/output exclusively below factory package. `--renderer` hosts marshal actual witness graph into staged bridge transactions, native text measurement & UIA semantics. Current adapter handles Text/Button/container/modifier nodes, aborting unsupported node kinds. Palette/font defaults are factory host behavior, distinct from native SwiftUI oracle. No Mac expected output controls Windows view.

`compile-probe.ps1` never executes renderer host. Optional headless layout collection is marked `runtime.layout.observational`, uses fixed-advance measurer & grants no native parity. Smoke manifests with `executionEligible:false` are compile-only.

`run-native.ps1 -Package <path> -RunRoot <fresh-path>` waits at most six minutes for free desktop lock, atomically claims its own token, starts hidden interactive scheduled task, bounds job at ten minutes & releases only its own token. Busy owners remain intact. Own scheduled task & receipt remain saved. No remote files/tasks are deleted.

`capture-native.ps1` performs 20 independent eligible renderer launches under exact coordinator token. Test windows move behind user windows without activation; UIA queries target probe HWND. Raw UIA, host logs & native screen crops receive case/source/executable/renderer hash bindings. Background crops retain observed screen pixels; their occlusion remains unqualified. Pixel/UIA evidence is independent from provider observations & never automatically promoted to parity PASS.

Unit guards:

```sh
python3 -m unittest factory.native.windows.test_adapter -v
```

Normalization archives `run-001/capture.json` through `run-020/capture.json`, each beside exact raw row files, `Witness.swift`, `plan.json`, `native-observation.json`, `tuple.json` & optional compiled `FactoryProbe.exe`. Source, plan, receipt, UIA & PNG hashes bind copied bytes. All 20 receipts validate before archive writes; path escape, overwrite & late raw drift fail. Synthetic unit markers propagate into capture conditions & cannot count as native evidence.

Renderer consumers embed ComCtl v6 dependency & use GUI PE subsystem with `mainCRTStartup`. Capture rechecks subsystem2, starts without shell/console, installs thread CBT activation/focus veto before synchronous renderer startup & aborts on any observed owned foreground PID through startup/capture/exit. Foreground HWND/class/title, launch policy & owned process identity remain in raw archives; failures retain evidence without restoring focus.
