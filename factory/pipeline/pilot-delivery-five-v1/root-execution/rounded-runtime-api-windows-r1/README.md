# Rounded runtime API Windows test packet r1

Source-only packet. Root invokes `root-test-rounded-api-r1.ps1` through existing Windows transport after Image work completes.

Entry stages 61 hash-pinned files (58 API6 closure rows + 3 Rounded files) into `D:\Claude\swiftright\.factory-work\runtime-stage\api-rounded-r1`, sets same Swift 6.4 SDK/DLL environment as R8, then runs release XCTest filter `ContinuousRoundedGeometryTests` with one job/frontend thread. It requires 2 GiB compiler budget & 180-second deadline. No Windows action was dispatched during preparation.
