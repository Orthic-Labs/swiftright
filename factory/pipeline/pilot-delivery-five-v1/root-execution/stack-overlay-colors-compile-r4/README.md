# Stack overlay colors compile r4 source-only request

Prospective v8 installation into rolling `D:\Claude\swiftright\.factory-work\hosts\stack-overlay-colors`; no fourth stage. Prior stage must be moved intact to `D:\Claude\swiftright\.factory-work\retired\stack-overlay-colors-v7-observed-20261012-2150` before staging.

- packet: `factory/pipeline/pilot-delivery-five-v1/stack-layout/stack-overlay-centered-execution-v8`
- candidate: `swiftui.stack-overlay.centered-host.execution-v8-native-body-policy`
- compile plan SHA256: `sha256:57c6670ef57c0cad294250e48370f08603cf7a990d71e403f25a2127c63c77b4`
- package plan SHA256: `sha256:bada33b6f865ab00d4529398ac886ec0e41a5940f22a3d6252c263c338491228`
- source bindings: `sha256:0160b8e9dcbc8d7751b5e9ecfa97161595197598dbbdcf1333f2a7d457581c8f`
- original witness SHA256: `sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee`
- shared body resolver SHA256: `sha256:f8f5da702526ad9136cbd2c801fd66229727ec88954ec3a26eab968cf757b212`
- source rows: 12; runtime receipt/tree remain pinned; body profile uses native DPI/font metrics.
- staging entry SHA256: `sha256:8d64ab099972e33d71aaa19e64e156aaa11b33f05b9453b9e7084dcede0b0aa7`
- builder SHA256: `sha256:dc8c7b6fe4a46d5c5438b455bd9de77b34ecbbd8decfe76e7ce9244c191e9dbd`; helper SHA256: `sha256:112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e`

`stage-build-r4-stack-v8.ps1` refuses an existing package/stale evidence, writes exact source rows, installs package/compile plans, runs builder preflight, then invokes existing one-job/1 GiB compile path. Historical r3 remains untouched.

Root staging command: `& .\stage-build-r4-stack-v8.ps1`
