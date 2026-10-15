#!/bin/sh
# usage: restage.sh <work dir name> : refresh the probe-patched stage copy from the pristine stage and re-apply every probe patch (never deletes)
set -eu; H="$(cd "$(dirname "$0")" && pwd)"; N="$1"; W='D:\Claude\swiftright\.work\'$N
scp -q "$H/runtime-patch/patch_host.py" "$H/runtime-patch/ProbePatch.swift" "win:D:/Claude/swiftright/.work/$N/"
ssh win "\$w='$W'; \$s='D:\\Claude\\swiftright\\.factory-work\\product-stage\\8bf89d2dc-aa6cd909'; \$d=\"\$w\\stage-patched\"; \$h=\"\$d\\packages\\SwiftRightHost\\Sources\\SwiftRightHost\"; \$r=\"\$d\\probes\\sr0-s\\fresh-runtime\\Sources\\SwiftRightRuntime\"
foreach(\$f in 'BridgeTextMeasurer.swift','ResolvedNodePainter.swift','SystemImages.swift','ButtonPainter.swift'){ Copy-Item \"\$s\\packages\\SwiftRightHost\\Sources\\SwiftRightHost\\\$f\" \$h -Force }
foreach(\$f in 'ContinuousRoundedGeometry.swift','ContinuousRoundedRasterizer.swift'){ Copy-Item \"\$s\\probes\\sr0-s\\fresh-runtime\\Sources\\SwiftRightRuntime\\\$f\" \$r -Force }
Copy-Item \"\$w\\ProbePatch.swift\" \$r -Force
Copy-Item \"\$s\\packages\\SwiftRightBridge\\Sources\\SwiftRightBridge\\Marshal.swift\" \"\$d\\packages\\SwiftRightBridge\\Sources\\SwiftRightBridge\" -Force
py -3 \$w\\patch_host.py \$h 2>&1 | select -last 4"
