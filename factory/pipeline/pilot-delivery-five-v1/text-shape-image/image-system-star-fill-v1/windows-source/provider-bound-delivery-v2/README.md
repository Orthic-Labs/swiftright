# Windows star.fill provider-bound source packet v2

This packet copies `compiler-ready-v1` & replaces its placeholder map with r4 measured provider output. Original `Image(systemName: "star.fill")` witness remains unchanged. Map identity is Segoe Fluent Icons `E735`; provider raw RGBA is retained at `provider-evidence/star-fill.rgba.bin` (4080 bytes, `sha256:6a8be6929a9243dd5f5e4fb4c7cc6dd03feff282437109c20128733e63cd7594`).

`FactorySystemImageRegistry` consumes `package/FactorySystemImageAssets.json`, validates identity/status/size/hash, registers one ABI 0.6 RGBA handle, & releases it at teardown. `main.swift` keeps provider requirements empty because measured map path is executable; registry validation remains active. No SF Symbol name substitution, Mac golden asset, or expected-pixel fixture is included. `licenseStatus` remains factual `unverified` metadata & is not a local startup gate.

Mac source packet `image-system-star-fill-v1/mac-source` wraps same witness in fixed 320x240 `topLeading` root. Windows packet retains full-client 320x240 proposal & top-leading placement to match that host context; no centering transform is added.

Root should copy this packet into fresh canonical `.factory-work` stage, run existing bounded compiler/capture orchestration, then join EXE/native/UIA/paired Mac receipts. Provider r4 receipts are copied under `provider-evidence/`; archive source is recorded in `provider-evidence/join.json`.
