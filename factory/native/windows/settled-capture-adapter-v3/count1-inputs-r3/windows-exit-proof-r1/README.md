# Windows exit-proof builder r1

`build-windows-exit-proof-r1.py` attaches `meta.conditions.windowsExitProof` only after reading actual typed captures & exact raw source-map bytes. It preserves capture fields, emits per-run `archiveBindings`, & fails closed when any compile stream, compiler tool, host source, runtime module, or proof role is unavailable.

Production proof has 13 gate roles (`outcome`, `observation`, `owned`, `close`, `plan`, `compile`, `witness`, `exe`, `renderer`, `runtimeReceipt`, `runtimeTree`, `stdout`, `stderr`). Compiler tool, host source, runtime members, & observation raw files remain explicit transitive archive bindings; no proof hash is inferred from metadata.

Root command after typed captures exist:

```sh
python3 factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r1/build-windows-exit-proof-r1.py \
  --captures <actual-typed-captures.json> \
  --input-map <actual-count-input-map.json> \
  --source-root <transport-root> \
  --compiler <transported-compiler-bytes> \
  --require-complete \
  --output <fresh-proof-bundle.json>
```

Last working Count1 source test returns blocked honestly: `adapter typed captures unavailable: typedStatus held; no exit proof attached`. It does not create native effects, lock effects, remote effects, or synthetic proof objects.
