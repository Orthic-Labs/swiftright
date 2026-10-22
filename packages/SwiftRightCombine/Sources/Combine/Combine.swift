// The Combine module on platforms without Apple's (#88): the vendored OpenCombine re-exported (with its Apple-named Schedulers, NotificationCenter.publisher,
// Timer.publish always compiled in: Vendor/README.md), plus what it lacks:
//   - Publishers.CombineLatest / CombineLatest3 and Publisher.combineLatest, Publishers.Merge / Merge3 / MergeMany and Publisher.merge(with:)
//     (absent from OpenCombine 0.14).
// Measured on the Dell (Swift 6.4, Windows): OpenCombine 0.14.0 builds and runs ObservableObject, @Published, $property publishers, subjects, Future,
// NotificationCenter publishing and DispatchQueue scheduling.
#if canImport(Darwin)
#error("SwiftRightCombine is for platforms without Apple's Combine; depend on it only for .windows/.linux")
#endif

@_exported import OpenCombine
@_exported import OpenCombineFoundation
@_exported import OpenCombineDispatch
import Foundation
import Dispatch
