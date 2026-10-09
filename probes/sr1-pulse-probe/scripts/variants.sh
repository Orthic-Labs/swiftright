#!/bin/sh
# Builds out/variants/{full,nogaps,raw}: full = spliced + gap-fill stubs; nogaps = spliced, no
# gap-fill (raw type-resolution errors); raw = nothing cut or filled (AppKit island included).
# build scripts then copy one variant over out/src. out/ is git-ignored.
cd "$(dirname "$0")/.." || exit 1
for v in full nogaps raw; do
  case $v in full) env SPLICE=1 scripts/prepare.sh;; nogaps) env SPLICE=1 NOGAPS=1 scripts/prepare.sh;; raw) env SPLICE=0 NOGAPS=1 scripts/prepare.sh;; esac
  mkdir -p out/variants/$v
  cp out/src/*.swift out/variants/$v/
  # drop files not in this variant (a previous prepare may have left extras)
  [ $v != full ] && rm -f out/variants/$v/Gaps.swift out/variants/$v/GapsModifiers.swift
done
env SPLICE=1 scripts/prepare.sh
