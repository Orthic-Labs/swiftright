# Pilot continuation v1: Toggle & disabled

Source-only continuation for two held control-state candidates selected by `next-pilot-admission-v1`. `prepare_control_state_inputs.py` verifies exact generated source, manifest & canonical recipe bytes, then emits fresh `host-inputs.json` & `adapter-plan.json` under a new output directory. It streams bounded files, rejects symlinks/growth, refuses overwrite, and performs no compiler, capture, provider, GUI, lock, remote, or native action.

Toggle inputs are `initial=false`, `style=automatic`, `Toggle("Enabled", isOn:)`. Disabled inputs are `disabled=true`, light color scheme, `Button("Continue"){}.disabled(true)`. API availability is source-reviewed only in `api-availability.json`: Toggle paint is held under ABI0.6; disabled provider action-state is unmeasured.

Adapter plan derives reviewed Text/Circle machinery by contract: Mac uses same-group background capture & fresh host/compiler receipt; Windows uses source-bound generic plan/capture interfaces, MTA UIA closure, 1 GiB job, retained handles, stream seals, & per-run terminal proof. Profile-specific Toggle/disabled plan builders remain required; no Text/Circle IDs, receipts, binaries, or captures are reused.

Root commands, each with fresh ignored output:

```sh
python3 factory/pipeline/pilot-next-source-v1/pilot-continuation-v1/prepare_control_state_inputs.py \
  --block toggle \
  --source factory/probes/generated/factory.probes.smoke.swiftui.toggle.swift \
  --manifest factory/probes/generated/factory.probes.smoke.swiftui.toggle.manifest.json \
  --recipe factory/recipes/data/swiftui.toggle.json \
  --output factory/native/windows/.work/control-state-toggle-source-r1

python3 factory/pipeline/pilot-next-source-v1/pilot-continuation-v1/prepare_control_state_inputs.py \
  --block disabled \
  --source factory/probes/generated/factory.probes.smoke.swiftui.disabled.swift \
  --manifest factory/probes/generated/factory.probes.smoke.swiftui.disabled.manifest.json \
  --recipe factory/recipes/data/swiftui.disabled.json \
  --output factory/native/windows/.work/control-state-disabled-source-r1
```

After source preparation, root must create profile-specific Mac/Windows compiler plans from measured source bytes, then fresh Count1 source admission before Count20. Required joins are listed in `adapter-plan.json`; missing host/compiler/provider evidence keeps candidate held. Existing generated manifests remain `executionEligible=false`.
