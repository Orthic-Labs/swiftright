#!/bin/sh
# Re-stamps the capture host into every case package (run from this directory after editing CaptureHost.template.swift or the product API).
set -e
cd "$(dirname "$0")/.."
S=shared-windows-host/stamp-case.py; R=text-shape-image/rounded-stroke-host-v1; I=text-shape-image/image-system-star-fill
# Centre through the runtime (a ZStack in a viewport-sized frame, exactly what the Mac hosts do), never by translating the finished tree (--centered):
# SwiftUI snaps absolute edges, so a layout snapped relative to a translated root rounds half-pixel ties by the wrong value (docs: blocks-6-10/pixel-ties/README.md).
C() { echo "ZStack(alignment: .center) { $1 }.frame(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale), alignment: .center)"; }
python3 $S stack-layout/custom-layout-host-v2/light-centered-execution-v4 --witness "$(C 'Witness_custom_layout()')"
python3 $S stack-layout/custom-layout-host-v2/rtl-original-execution-v1 --witness "$(C 'Witness_custom_layout()')"
for c in continuous-geometry-delivery-v2 gen-small-r4-s1 gen-large-r40-s8 gen-wide-r12-s3; do python3 $S $R/$c --witness "$(C 'Witness_shapes_fill_stroke()')"; done
# the 45x25 case centres through the runtime (ZStack in a viewport-sized frame, as the Mac host does) so edges snap where SwiftUI snaps them
python3 $S $R/gen-frac-r6-s2-45x25 --witness 'ZStack(alignment: .center) { Witness_shapes_fill_stroke() }.frame(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale), alignment: .center)'
python3 $S stack-layout/stack-overlay-centered-execution-v9 --witness "$(C 'Witness_stack_overlay()')"
python3 $S text-shape-image/bundled-font-readiness-v6-line-limit-host --witness 'Witness_tinos_bundled_text_pilot()'
for c in v10 gen-16pt gen-120x60 gen-48pt; do python3 $S $I-$c --witness 'Witness_image_baseline()'; done
