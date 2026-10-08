import Foundation

public struct FixtureConfig: Sendable {
    public enum Fixture: String, CaseIterable, Sendable {
        case F1, F2, F3, F4, F5, F6, F7, F8, F9

        public var number: Int {
            (Self.allCases.firstIndex(of: self) ?? 0) + 1
        }
    }

    /// Container used by F3 only. `list` is the original fixture; the others are oracle variants.
    public enum F3Container: String, Sendable, CaseIterable {
        case list, vstack, lazy
    }

    public let fixture: Fixture
    public let selfTest: Bool
    public let eventsPath: String?
    public let reducedMotion: Bool
    public let f3Container: F3Container
    /// Milliseconds between removal and reinsertion in F3; 0 is the original immediate reinsert.
    public let f3GapMs: Int
    /// Variant name as passed on the command line, e.g. `list-1s`; nil when no variant was requested.
    public let f3VariantName: String?

    /// Parses `--fixture F1..F9`, `--events <path>`, `--reduced-motion-variant`,
    /// `--f3-variant <list|vstack|lazy>-<1|3>s`, and `--self-test`.
    /// `--self-test` must come last: AppKit treats a trailing bare path as a document and suppresses the window.
    public static func parse(_ arguments: [String]) -> FixtureConfig {
        var fixture = Fixture.F1
        var selfTest = false
        var events: String?
        var reduced = false
        var container = F3Container.list
        var gap = 0
        var variantName: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--fixture":
                index += 1
                if index < arguments.count, let parsed = Fixture(rawValue: arguments[index]) {
                    fixture = parsed
                }
            case "--self-test":
                selfTest = true
            case "--events":
                index += 1
                if index < arguments.count { events = arguments[index] }
            case "--reduced-motion-variant":
                reduced = true
            case "--f3-variant":
                index += 1
                if index < arguments.count, let parsed = parseF3Variant(arguments[index]) {
                    variantName = arguments[index]
                    container = parsed.container
                    gap = parsed.gapMs
                } else {
                    FileHandle.standardError.write(Data("invalid --f3-variant\n".utf8))
                    exit(2)
                }
            default:
                break
            }
            index += 1
        }
        return FixtureConfig(
            fixture: fixture, selfTest: selfTest, eventsPath: events, reducedMotion: reduced,
            f3Container: container, f3GapMs: gap, f3VariantName: variantName
        )
    }

    static func parseF3Variant(_ name: String) -> (container: F3Container, gapMs: Int)? {
        let parts = name.split(separator: "-")
        guard parts.count == 2,
              let container = F3Container(rawValue: String(parts[0])),
              parts[1].hasSuffix("s"),
              let seconds = Int(parts[1].dropLast()),
              [1, 3].contains(seconds) else { return nil }
        return (container, seconds * 1000)
    }
}
