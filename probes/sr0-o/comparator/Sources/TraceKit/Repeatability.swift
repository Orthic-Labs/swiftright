import Foundation

public struct RepeatabilityReport: Codable, Sendable, Equatable {
    public var runs: Int
    public var allAgree: Bool
    public var disagreeingPaths: [String]   // "step path", unique, sorted
    public var flaggedRuns: [Int]           // 1-based runs that disagree with run 1
    public var errors: [String]
}

public enum Repeatability {
    /// Run 1 is the reference. Every other run is compared with the same exact comparator.
    public static func check(_ traces: [Trace], adaptations: [Adaptation] = []) -> RepeatabilityReport {
        guard let reference = traces.first else {
            return RepeatabilityReport(runs: 0, allAgree: false, disagreeingPaths: [], flaggedRuns: [], errors: ["no traces given"])
        }
        var paths = Set<String>()
        var flagged: [Int] = []
        var errors: [String] = []
        for (offset, trace) in traces.enumerated().dropFirst() {
            let run = offset + 1
            if trace.fixtureId != reference.fixtureId {
                errors.append("run \(run): fixture \(trace.fixtureId) differs from \(reference.fixtureId)")
            }
            let report = TraceComparator.compare(accepted: reference, candidate: trace, adaptations: adaptations)
            if !report.passed { flagged.append(run) }
            for d in report.diffs { paths.insert("\(d.step) \(d.path)") }
        }
        return RepeatabilityReport(
            runs: traces.count,
            allAgree: flagged.isEmpty && errors.isEmpty,
            disagreeingPaths: paths.sorted(),
            flaggedRuns: flagged,
            errors: errors
        )
    }
}
