#!/usr/bin/env bash
# CI gate for the right-git ci lane. Proves the sparse checkout carries every input the packaging lanes need,
# on the runner OS that checked it out (the Windows leg is the one that used to fail with "Filename too long").
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
dll="probes/sr0-s/fresh-on-bridge/out/tuple12-renderer-recovery-v1/recovered-artifacts-r3/swiftright_render.dll"
required=(
  "examples/SliceApp/Package.swift"
  "examples/SliceApp/right-release.config.mjs"
  "examples/SliceApp/Windows/renderer-pin.json"
  "render/swiftright-render/Cargo.toml"
  "$dll"
)
for path in "${required[@]}"; do
  [[ -e "$path" ]] || { echo "::error::missing from checkout: $path"; exit 1; }
done
[[ -d packages ]] || { echo "::error::missing from checkout: packages/"; exit 1; }
[[ -d probes/sr0-s/fresh-runtime ]] || { echo "::error::missing from checkout: probes/sr0-s/fresh-runtime"; exit 1; }
sum="$(sha256sum "$dll" | cut -d' ' -f1)"
echo "tuple 12 renderer DLL sha256 $sum"
case "$sum" in
  7578cd5d*) ;;
  *) echo "::error::tuple 12 renderer DLL hash $sum does not start with 7578cd5d"; exit 1 ;;
esac
echo "tracked files in sparse checkout: $(git ls-files | wc -l | tr -d ' ')"
