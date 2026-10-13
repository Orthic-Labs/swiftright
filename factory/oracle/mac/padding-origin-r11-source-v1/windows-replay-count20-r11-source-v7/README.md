# Fresh Count20 r11 metadata controls source-v7

v7 is immutable source-only successor to v6 controls. It requires fresh absolute `ControlRoot` inside producer root, refuses pre-existing roots/output, writes all resealed mutations for audit, & performs no TempPath cleanup or deletion. Baseline plus relocated positive plus 11 actual metadata/tuple/binding mutations call frozen `Assert-LeaseIssuedMetadata`; each fault must reject with expected guard reason & zero native actions. Receipt shape is `factory-issued-metadata-full-guard-controls-v1`.

Stage beside v6 integration source & invoke `test-full-metadata-controls-v7.ps1` before native launch. ControlRoot must be fresh repo-owned `.factory-work/...` child.
