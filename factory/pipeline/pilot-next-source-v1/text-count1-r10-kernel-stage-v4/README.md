# Text Count1 r10 kernel stage v4

Source-only staging pack for fresh namespace `text-mta-r11-count1-r10`.
It copies frozen `capture-count1-r5g-sources`, keeps proven `count1-r5` leaf
paths, reseals candidate graph, worker contract, integration bindings & source
inputs, then installs root-v3 retained-kernel cleanup into both cleanup roles.
Renderer & UIA final-exit certificates remain separate. Cleanup callsites carry
one `-ExpectedExeHash $ExeHash` capture binding & one
`-ExpectedExeHash $exeHash` MTA-worker binding.

Measured donor joins:

- `host-plan.json` raw SHA256:
  `de8660b0c55a717d52171ec476b833881919696f434c3ceba077ba3b77fbc642`
- Text source SHA256:
  `4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e`
- Windows executable SHA256:
  `33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7`
- root-v3 cleanup SHA256:
  `cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13`

Canonical case hashes remain canonical values from donor plan; they are never
compared with raw case-file SHA256. Package bounds are 256 files, 8 MiB/file &
32 MiB total. Stager performs no native, compiler, lock or remote action.

Root invocation, after selecting fresh output paths under existing rolling
Text host tree:

```text
python3 factory/pipeline/pilot-next-source-v1/text-count1-r10-kernel-stage-v4/stage_text_count1_r10_v4.py --profile text --donor-root factory/native/windows/pilot-text-paint-root-v2/capture-count1-r5g-sources --installer-template factory/native/windows/pilot-text-paint-root-v2/install-count1-r5g-mta.ps1 --output-root <fresh-package> --output-zip <fresh-package.zip> --output-installer <fresh-install.ps1> --namespace text-mta-r11-count1-r10 --old-namespace text-mta-r11-v5g --new-count-token count1-r5
```

Installer performs bounded package verification, PowerShell parse checks,
MTA-config controls, source-graph integration admission & headless coordinator
preflight before any native action. Existing donor outputs remain immutable.
