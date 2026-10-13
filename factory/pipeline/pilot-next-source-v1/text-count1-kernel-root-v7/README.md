# Text Count1 kernel-root v7

v6 native admission passed, then failed before renderer launch because stale callers referenced `FactoryProcessWaitV5` while root-v3 cleanup defines `FactoryProcessWaitV6`. v7 is additive: it copies v6 source, rewrites only stale direct wait-type references, & runs a bounded source control before issuer, scheduler, lock, or native actions. Root-v3 cleanup remains authoritative for type loading, retained original handles, kernel exit authority, 30s renderer, 15s exit, 5s drain, memory, UIA, & release predicates remain unchanged.

Source-only preparer command, run by root after review:

```text
python3 factory/pipeline/pilot-next-source-v1/text-count1-kernel-root-v7/prepare_text_count1_kernel_root_v7.py --profile text --donor-root factory/native/windows/pilot-text-paint-root-v2/capture-count1-r11-root-v6-sources --installer-template factory/native/windows/pilot-text-paint-root-v2/install-count1-r11-root-v6-r1.ps1 --output-root factory/pipeline/pilot-next-source-v1/text-count1-kernel-root-v7/generated/text-mta-r11-count1-r12 --output-zip factory/pipeline/pilot-next-source-v1/text-count1-kernel-root-v7/generated/text-mta-r11-count1-r12.zip --output-installer factory/pipeline/pilot-next-source-v1/text-count1-kernel-root-v7/generated/install-text-mta-r11-count1-r12.ps1 --namespace text-mta-r11-count1-r12 --new-count-token count1-r5
```

Installer runs `test-factory-process-wait-v7.ps1` before MTA controls, issuer, integration, & coordinator preflight. It dot-sources root-v3 cleanup, proves `FactoryProcessWaitV6` loaded, rejects `FactoryProcessWaitV5` callers, & verifies cleanup loads before every direct V6 call. It reports native/lock/compiler actions as zero.
