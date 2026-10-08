import Foundation

public struct FixtureConfig: Sendable {
    public enum Fixture: String, CaseIterable, Sendable {
        case F1, F2, F3, F4, F5, F6, F7, F8, F9

        public var number: Int {
            (Self.allCases.firstIndex(of: self) ?? 0) + 1
        }
    }

    public let fixture: Fixture
    public let selfTest: Bool
    public let eventsPath: String?
    public let reducedMotion: Bool

    /// Parses `--fixture F1..F9`, `--self-test`, `--events <path>`, `--reduced-motion-variant`.
    public static func parse(_ arguments: [String]) -> FixtureConfig {
        var fixture = Fixture.F1
        var selfTest = false
        var events: String?
        var reduced = false
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
            default:
                break
            }
            index += 1
        }
        return FixtureConfig(fixture: fixture, selfTest: selfTest, eventsPath: events, reducedMotion: reduced)
    }
}
