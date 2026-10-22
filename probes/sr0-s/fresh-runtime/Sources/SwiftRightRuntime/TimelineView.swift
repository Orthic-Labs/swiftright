import Foundation

// Issue #82 (SR2 S2): TimelineView. The host clock (`Graph.tick(now:)`, seconds with no required origin) is the timeline's time: a context date is
// `Date(timeIntervalSinceReferenceDate: now)`. Every TimelineView reads one observable clock source, so a tick re-evaluates its content; a schedule only quantizes the
// date it hands to the content (periodic: the last due step at or before now; explicit: the last listed date at or before now; animation: now). Before the first tick
// the content sees `Date(timeIntervalSinceReferenceDate: 0)` for animation and periodic schedules, and the first explicit date.
// Not modelled: pausing (`TimelineScheduleMode.lowFrequency`), `minimumInterval` throttling, and dates between ticks.

/// The host clock as observable state.
@Observable @MainActor
final class TimelineClockSource {
    static let shared = TimelineClockSource()
    var now: Double = 0
}

/// Apple: https://developer.apple.com/documentation/swiftui/timelineschedule
public protocol TimelineSchedule: Sendable {
    /// The date this schedule hands out at host time `now` (a date at or before `now`, except the first of an explicit schedule).
    func date(at now: Date) -> Date
}

/// Apple: https://developer.apple.com/documentation/swiftui/animationtimelineschedule
public struct AnimationTimelineSchedule: TimelineSchedule {
    public init(minimumInterval: Double? = nil, paused: Bool = false) {}
    public func date(at now: Date) -> Date { now }
}

/// Apple: https://developer.apple.com/documentation/swiftui/periodictimelineschedule
public struct PeriodicTimelineSchedule: TimelineSchedule {
    let start: Date, interval: TimeInterval
    public init(from start: Date, by interval: TimeInterval) { self.start = start; self.interval = interval }
    public func date(at now: Date) -> Date {
        guard interval > 0, now >= start else { return start }
        return start.addingTimeInterval((now.timeIntervalSince(start) / interval).rounded(.down) * interval)
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/explicittimelineschedule
public struct ExplicitTimelineSchedule: TimelineSchedule {
    let dates: [Date]
    public init(_ dates: [Date]) { self.dates = dates.sorted() }
    public func date(at now: Date) -> Date { dates.last(where: { $0 <= now }) ?? dates.first ?? now }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule { AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused) }
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    public static func periodic(from start: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule { PeriodicTimelineSchedule(from: start, by: interval) }
}

extension TimelineSchedule where Self == ExplicitTimelineSchedule {
    public static func explicit<S: Sequence>(_ dates: S) -> ExplicitTimelineSchedule where S.Element == Date { ExplicitTimelineSchedule(Array(dates)) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/timelineview/context
/// (declared outside the generic view so that a content closure's parameter type does not depend on the closure's own result type)
public struct TimelineViewContext {
    public enum Cadence: Int, Comparable, Sendable {
        case live, seconds, minutes
        public static func < (a: Cadence, b: Cadence) -> Bool { a.rawValue < b.rawValue }
    }
    public let date: Date
    public let cadence: Cadence
    public var isPaused: Bool { false }
}

/// Apple: https://developer.apple.com/documentation/swiftui/timelineview
public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    public typealias Context = TimelineViewContext

    let schedule: Schedule
    let content: (Context) -> Content

    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (Context) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    @MainActor public var body: some View {
        let now = Date(timeIntervalSinceReferenceDate: TimelineClockSource.shared.now)
        return content(TimelineViewContext(date: schedule.date(at: now), cadence: .live))
    }
}
