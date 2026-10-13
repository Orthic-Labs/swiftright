# Independent capture caller source review v1

Stage 04e544f5044707a31ce2326c8bf0c3b8e5e14155fbb16e527703092c17605247; runner fe80ada6556ec763776e6744bfc0f2b0dc3d33d6e629c724a71737246827fddf; coordinator a21530a46e33beb21ff0346229914482a1452706eeb706b14f67202f3f52016d; combined release 64205826d6b8371bf5ba9f3cbcc5a1cb4d8a7e55bcd7a8f29e5fee92db15c128.

Verdict: HOLD_SOURCE.

Actual lease build receipt 1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf & executable 3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a bind exact plan/source/runtime/compiler/renderer bytes, owned exit 0, kernel wait 0, and sealed raw streams. Caller source verifies Count1 then Count20, exact explicit40 lease, prelaunch null identities, UIA before pixels/WM_CLOSE, renderer + worker release joins, and 15s/5s bounds.

Blocker: coordinator finally sets releaseAllowed true after hold-harness-error when taskResult.workerInventories and native directory set are both empty. No explicit source-owned no-invocation proof exists in this path, so unknown/failed interactive start can release desktop lock. Require completed source-bound status with exhaustive inventory, or durable no-invocation proof for every predeclared slot.
