import SwiftRightSentinel

print("sentinelAdd(2, 3) = \(sentinelAdd(2, 3))")

switch checkABI() {
case .success(let report):
    print("expectedSize = \(report.expectedSize)")
    print("fullSize -> \(report.fullSize)")
    print("tooSmallCallerSize = \(report.tooSmallCallerSize) -> \(report.tooSmallSize)")
    print("tooSmallUntouchedStructSize = \(String(describing: report.tooSmallUntouchedStructSize))")
case .failure(let error):
    print("checkABI failed: \(error)")
}
