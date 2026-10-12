# Generic Text & Circle Windows capture adapters

Source-only adapter packet for measured Text `Aa` (system regular 24pt, 120x48 DIP) & Circle (40x40 DIP, `system.blue`, 320x240 DIP). It reuses reviewed renderer/UIA/stream/owned-release helpers; profile guards preserve exact plan, compile receipt, case, tuple, recipe, source, runtime, renderer, serializer, context, binding & integration rows.

Each profile has Count1 issuer, integration guard, preflight, dispatch, interactive task & capture sources. Count20 uses same source lineage only after successful fresh Count1 proof, with ordered `capture/<32hex>` & `image/<32hex>` IDs, separate first/repeat roots, all 20 per-run release proofs, 1 GiB self-job receipt, 30s window & 15s exit assertions. No native action is performed by this packet.

Root stages profile source rows beside producer support paths, binds measured plan/receipt/executable/renderer/tuple/case/context/binding/integration/serializer refs, then runs issuer, guard & preflight before root-owned native dispatch. Existing Text & Circle source inputs remain immutable; this packet emits no relabelled evidence.

Text assembly uses `text/integration.ps1`, `text/issue-metadata.ps1`, `text/prepare-plan.py`, `text/build-preflight.ps1`, Count1 scripts, Count20 scripts, & `Sr0OwnedJobProcess-v15.cs`. Circle assembly uses corresponding `circle/*` files plus measured Circle plan fields. Root must copy producer dependencies named by each profile source manifest into fresh producer/overlay roots & verify every row before invocation.

Suggested root sequence:

```text
1. Stage measured profile source-inputs & dependency rows into fresh producer/overlay roots.
2. Run profile build preflight with measured final plan/receipt/exe/renderer/source refs.
3. Run profile issuer Count1, then integration guard + Count1 dispatch `-PreflightOnly`.
4. Root launches Count1; only completed source-bound proof permits Count20 issuer/controller.
5. Run Count20 controller preflight, then root launches 20 ordered runs.
```

Failure controls must mutate one source/tuple/case/receipt/renderer/recipe/context/hash/count/ID field per run & verify rejection before lock/native action. Qualification/parity remains held.

Root command shape (replace each placeholder with measured, hash-bound path/ref; do not reuse donor IDs):

```powershell
# Count1 source plan & compile preflight
& .\text\prepare-plan.py --phase final --package $textPackage --runtime-package $runtimePackage --bridge-package $bridgePackage --compiler $compiler --renderer $renderer --source $textWitness --runtime-tree $runtimeTree --runtime-source-tree-hash $runtimeTreeHash --bridge-bindings $bridgeBindings --source-bindings $textSourceBindings --helper $helper --runtime-source-receipt $runtimeReceipt --runtime-verifier $runtimeVerifier --output $textPlan --case $textCase --expected-host-hash $textExeHash
& .\text\build-preflight.ps1 -PlanPath $textPlan -PlanSha256 $textPlanHash -Phase final -PreflightOnly
& .\text\issue-metadata.ps1 -Count 1 -SourceInputsPath $textInputs -SourceInputsHash $textInputsHash -OutputPath $textIssued -RunRoot $textRun -PlanPath $textPlan -PlanHash $textPlanHash -CompileReceiptPath $textReceipt -CompileReceiptHash $textReceiptHash -ExePath $textExe -ExeHash $textExeHash -RendererPath $renderer -RendererHash $rendererHash -SerializerPath $serializer -SerializerHash $serializerHash -TuplePath $textTuple -TupleHash $textTupleHash -BindingPath $textBinding -BindingHash $textBindingHash -RecipePath $textRecipe -RecipeHash $textRecipeHash
& .\text\interactive-single.ps1 -Config $textConfig -PreflightOnly

# Circle uses same sequence with .\circle\ paths & Circle measured plan fields.
# After Count1 proof is source-bound & completed, issue Count20 then run count20\controller.ps1 -Config $count20Config -PreflightOnly.
```

Before either sequence, stage full integration binding manifest (all measured rows, including context/tuple/binding/serializer/UIA/helper refs) under `$producerRoot`; pass exact source-input, plan, receipt, executable, renderer & recipe hashes. `-PreflightOnly` is root-run headless admission; native launch remains root-owned.
