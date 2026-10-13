import Foundation

// Factory diagnostic acquisition lease only; ordinary host default stays10s.
func factoryCaptureLeaseNanoseconds(_ arguments: [String]) throws -> UInt64 {
    if arguments.isEmpty { return 10_000_000_000 }
    guard arguments == ["--factory-capture-lease-seconds=40"] else {
        throw NSError(domain: "FactoryInvalidCaptureLease", code: 1)
    }
    return 40_000_000_000
}
