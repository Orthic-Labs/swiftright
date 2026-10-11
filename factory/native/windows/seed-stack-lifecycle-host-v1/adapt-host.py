#!/usr/bin/env python3
"""Reproduce diagnostic package from exact immutable parent. Fresh output only; --verify writes nothing."""
from pathlib import Path
import hashlib,json,argparse
sha=lambda b:hashlib.sha256(b).hexdigest()
PARENT='factory/native/windows/round1-seeded-hosts-v1/stack-overlay/package'
PINS={'Package.swift': '2c6efb7cb7d819d10defaf8fd49db7c5b049bbb204e4de93884ff420f86dcd0a', 'witness.manifest.json': 'b7a43fe22dd48c7326e5316712b14786442371df80cc0ff5aa957b1cd2f17c54', 'Sources/FactoryProbe/FactoryFill.swift': 'e06af75e3e8ecd0a28d55bb5520fff10e222ba84bfe3b8a52a5e1898fc9e3147', 'Sources/FactoryProbe/FactoryTextGeometry.swift': '1063aea5475987cb356ac31d67b965206a9ca6383bcd66ed1fc4c366dbaf7d43', 'Sources/FactoryProbe/FactoryViewport.swift': 'be3a8afa06db87d55d7aa07c52dde9a6b7a627ef51bf2f5269d148f23166d0ae', 'Sources/FactoryProbe/Witness.swift': 'fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35', 'Sources/FactoryProbe/main.swift': 'b2e6fde07c21274a7e74c8b47a9c3e11545215f2a0cd280ba6d0f19c86667e6c', 'Sources/FactoryProbe/FactoryContainer.swift': '742dba1f12b2b2969779b8e525bfb699238f898f951693b67449d3c1dedeffa4', 'plan.json': '4cc752eee6d227bf2fcbff60e2822f8199f233a904e1a8087f5a3ddd65f19f9b', 'runtime-source-receipt.json': 'b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7', 'runtime-source-tree.json': 'c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'}
REPLACEMENTS=[('import WinSDK\n', 'import WinSDK\n\n// Diagnostic-only lifecycle observer: wall clock correlates coordinator receipts; tick clock is monotonic.\nfunc factoryLifecycle(_ event: String) {\n    let utc = Date().timeIntervalSince1970\n    print("FACTORY_LIFECYCLE event=\\(event) utcEpochSeconds=\\(utc) tickMS=\\(GetTickCount64()) pid=\\(GetCurrentProcessId()) thread=\\(GetCurrentThreadId())")\n    fflush(stdout)\n}\n'), ('let result: Int32 = MainActor.assumeIsolated {', 'factoryLifecycle("actor-enter")\nlet result: Int32 = MainActor.assumeIsolated {\n    defer { factoryLifecycle("actor-scope-defer") }'), ('        bridge.onWindowClosed = { MainActor.assumeIsolated {\n            host.graph?.tearDown()\n            host.measurer?.releaseAll()\n            do { try bridge.shutdownComplete() } catch { host.errors.append(String(describing: error)) }\n        } }', '        bridge.onWindowClosed = { MainActor.assumeIsolated {\n            factoryLifecycle("window-closed-enter")\n            host.graph?.tearDown()\n            factoryLifecycle("graph-teardown-return")\n            host.measurer?.releaseAll()\n            factoryLifecycle("measure-release-return")\n            do { try bridge.shutdownComplete() } catch { host.errors.append(String(describing: error)) }\n            factoryLifecycle("shutdown-complete-return")\n        } }'), ('        defer { UnhookWindowsHookEx(activationHook) }', '        defer {\n            factoryLifecycle("unhook-enter")\n            UnhookWindowsHookEx(activationHook)\n            factoryLifecycle("unhook-return")\n        }'), ('        try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)', '        factoryLifecycle("bridge-run-enter")\n        try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)\n        factoryLifecycle("bridge-run-return")'), ('fflush(stdout)\nexit(result)\n', 'factoryLifecycle("actor-return-result-\\(result)")\nfflush(stdout)\nfactoryLifecycle("before-exit-result-\\(result)")\nexit(result)\n')]
a=argparse.ArgumentParser();a.add_argument('--repo',default='.');a.add_argument('--output');a.add_argument('--verify',action='store_true');args=a.parse_args()
base=Path(args.repo);src=base/PARENT;dst=Path(args.output) if args.output else Path(__file__).resolve().parent/'package'
original={f:(src/f).read_bytes() for f in PINS}
for f,b in original.items():
    if sha(b)!=PINS[f]:raise SystemExit('Immutable parent drift: '+f)
content=dict(original);main=content['Sources/FactoryProbe/main.swift'].decode()
for old,new in REPLACEMENTS:
    if main.count(old)!=1:raise SystemExit('Exact adapter preimage mismatch: '+repr(old))
    main=main.replace(old,new)
content['Sources/FactoryProbe/main.swift']=main.encode()
plan=json.loads(original['plan.json'])
for binding in plan['sourceBindings']:
    if binding['path']=='Sources/FactoryProbe/main.swift':binding['sha256']='sha256:'+sha(main.encode())
plan['diagnosticScope']='factory-stack-host-lifecycle-v1'
plan['diagnosticEvidence']='Lifecycle localization only; excluded from native parity/repetition witnesses.'
plan['diagnosticLineage']={'parentPlanSha256':'sha256:'+PINS['plan.json'],'parentMainSha256':'sha256:'+PINS['Sources/FactoryProbe/main.swift'],'adapterSha256':'sha256:'+sha(Path(__file__).read_bytes()),'witnessUnchanged':True,'quitThresholdUnchanged':True,'runtimeBridgeCompilerBindingsUnchanged':True}
content['plan.json']=(json.dumps(plan,indent=2)+'\n').encode()
if args.verify:
    for f,b in content.items():
        if (dst/f).read_bytes()!=b:raise SystemExit('Diagnostic package drift: '+f)
else:
    if dst.exists():raise SystemExit('Fresh output required')
    for f,b in content.items():
        p=dst/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
print(json.dumps({'verified':args.verify,'parentPlanSha256':PINS['plan.json'],'mainSha256':sha(main.encode()),'planSha256':sha(content['plan.json']),'witnessSha256':sha(content['Sources/FactoryProbe/Witness.swift'])},sort_keys=True))
