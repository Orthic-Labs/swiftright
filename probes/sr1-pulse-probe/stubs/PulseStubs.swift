// Minimal stand-ins for Pulse-internal model/design types the two probed files reference.
// Written from symbol usage only. No SwiftUI API is stubbed here: where a stub needs a SwiftUI
// type (Color, Font, Animation, Alignment) it uses the real name, so a missing one is reported
// as a missing SwiftUI symbol, attributed to this file.
import Foundation
import SwiftRightUI

// MARK: design tokens
enum Palette {
    static let textPrimary = Color.white
    static let textSecondary = Color.gray
    static let ringTrack = Color.gray
    static let card = Color.black
    static let barTrack = Color.gray
    static let critical = Color.red
    static let watch = Color.yellow
    static let ample = Color.green
    static let darkGlassTooltipDim = Color.black
    static let liquidGlassTooltipDim = Color.black
    static let readableTooltipTextSecondary = Color.gray
}

enum Design { static func px(_ v: CGFloat) -> CGFloat { v } }

enum Typography {
    static let percent = Font.caption
    static let percentPair = Font.caption
    static let percentAcross = Font.caption
    static let percentPairAcross = Font.caption
    static let percentAcrossSize: CGFloat = 12
    static let percentPairAcrossSize: CGFloat = 10
    static let cardTitle = Font.headline
    static let cardBody = Font.caption
}

enum NotchMotion {
    static let reading = Animation()
    static let crossfade = Animation()
}

enum NotchLayout {
    static let trackStroke: CGFloat = 3
    static let progressStroke: CGFloat = 3
    static let weeklyRingStroke: CGFloat = 1
    static let ringDiameter: CGFloat = 24
    static let activityDiameter: CGFloat = 18
    static let activityStroke: CGFloat = 1.5
    static let ringLabelGap: CGFloat = 2
    static let cellExtent: CGFloat = 40
    static let percentLineHeight: CGFloat = 12
    static let tailLength: CGFloat = 10
    static let tailHeight: CGFloat = 16
    static let cardCorner: CGFloat = 14
    static let cardWidth: CGFloat = 260
    static let cardPadding: CGFloat = 14
    static let cardTextWidth: CGFloat = 232
    static let headerGap: CGFloat = 8
    static let statusDotGap: CGFloat = 4
    static let statusDot: CGFloat = 10
    static let statusDotStroke: CGFloat = 1.5
    static let barHeight: CGFloat = 4
    static let moneyBarHeight: CGFloat = 4
    static let labelToBar: CGFloat = 4
    static let barToUsed: CGFloat = 4
    static let blockSpacing: CGFloat = 8
    static let moneyBarToStats: CGFloat = 6
    static let moneyStatGap: CGFloat = 2
    static let headerToBlock: CGFloat = 10
    static let hairline: CGFloat = 1
    static let codexUsageTop: CGFloat = 8
    static let codexUsageRowGap: CGFloat = 2
    static let codexResetCreditsHeight: CGFloat = 60
    static let sessionRowGap: CGFloat = 2
    static let defaultSessionCap = 4
    static func cardHeight(windowCount: Int, groupCount: Int, moneyWindowCount: Int, sessionCount: Int,
                           sessionCap: Int, statusMessage: String?, blockMessage: String?,
                           hasTokenUsage: Bool, hasPlan: Bool, hasResetCredits: Bool,
                           compactRowCount: Int) -> CGFloat { 200 }
}

enum NotchEdge {
    enum TooltipDirection { case leading, trailing, up, down }
}

// MARK: model
enum UsageBand: Equatable {
    case ample, watch, critical, exhausted
    static func band(for fraction: Double, watchLimit: Double, criticalLimit: Double) -> UsageBand { .ample }
    func color(accent: Color) -> Color { accent }
    static func rampColor(for fraction: Double, watchLimit: Double, accent: Color) -> Color { accent }
}

enum ProviderGlyph: Equatable { case send, claude, codex }
struct ProviderGlyphView: View {
    let glyph: ProviderGlyph
    var body: some View { EmptyView() }
}

enum WeeklyRing: Equatable {
    case off, inside, outside
    var radius: CGFloat? { self == .off ? nil : 10 }
}

enum ColorTransitionStyle: Equatable { case ramp, steps }

struct NotchSurfaceStyle {
    var isGlass = true
    var effective: NotchSurfaceStyle { self }
    static let glass = NotchSurfaceStyle()
    static let darkGlass = NotchSurfaceStyle()
    var glass: Int { 0 } // real one returns SwiftUI.Glass; shape not stubbed
    static func == (a: NotchSurfaceStyle, b: NotchSurfaceStyle) -> Bool { true }
}

enum Fidelity { case exact
    var qualifier: String { "" } }
enum ResetTimeFormat { case automatic }
enum ResetCopy {
    static func text(for date: Date, now: Date, format: ResetTimeFormat) -> String { "" }
    static func formatter(for calendar: Calendar) -> DateFormatter { DateFormatter() }
    static func daysApart(from: Date, to: Date, calendar: Calendar) -> Int { 0 }
}
enum ElapsedCopy {
    static func ago(since: Date, now: Date) -> String { "" }
    static func text(since: Date, now: Date) -> String { "" }
}
enum L10n {
    static func t(_ s: String) -> String { s }
    static let locale = Locale(identifier: "en_US_POSIX")
}
enum Percent { static func text(for f: Double) -> String { "" } }
enum Preferences { static let showUsagePaceKey = "showUsagePace" }

struct UsagePace { var summary: String; var isDeficit: Bool }
struct UsageMoneyBreakdown {
    var currency = "USD"
    var spentFraction = 0.0
    var spent = 0.0
    var remaining = 0.0
    var funded = 0.0
}
struct UsageResetCredits {
    var availableCount = 0
    var checkedAt: Date?
    var nextExpiry: Date?
}
struct LimitWindow: Identifiable {
    var id: String
    var label = ""
    var detail: String?
    var used: Int?
    var usedText: String?
    var usedFraction: Double?
    var trailingText: String?
    var resetsAt: Date?
    var money: UsageMoneyBreakdown?
    var summary = ""
    var group: String?
    var bandOverride: UsageBand?
    func usagePace(now: Date) -> UsagePace? { nil }
}
struct ProviderBlock { func summary(now: Date) -> String { "" } }
struct ProviderStatus { var isStale = false; var staleSince: Date? }
struct ProviderHeadline { var prefersUsedText = false }
struct ProviderSnapshot: Identifiable, Equatable {
    var id = ""
    var hasReading = true
    var ringFraction = 0.0
    var usedFraction: Double?
    var weeklyFraction: Double?
    var glyph = ProviderGlyph.claude
    var status = ProviderStatus()
    var block: ProviderBlock?
    var bandOverride: UsageBand?
    var displayName = ""
    var headlineText = ""
    var headline: ProviderHeadline?
    var windows: [LimitWindow] = []
    var plan: String?
    var headerAccessory: String?
    var statusMessage: String?
    var fidelity = Fidelity.exact
    var windowGroupCount = 0
    var tokenUsage: Int?
    var compactRowCount = 0
    func availableResetCredits(at now: Date) -> UsageResetCredits? { nil }
    static func == (a: ProviderSnapshot, b: ProviderSnapshot) -> Bool { a.id == b.id }
}

struct AgentSession: Identifiable {
    enum State { case busy, waiting, success, idle }
    var id = ""
    var name = ""
    var state = State.idle
    var waitingFor: String?
    var detail = ""
    var since = Date()
    var processID: Int32?
}
struct ActivitySummary: Equatable {
    enum State { case working, waiting, success, idle }
    var state = State.idle
    var queued = 0
    var color = Color.white
    var sessions: [AgentSession] = []
    static func == (a: ActivitySummary, b: ActivitySummary) -> Bool { true }
}

final class NearbySharing {
    static let pasteRowID = "paste"
    static let shared = NearbySharing()
    func pasteClipboard() {}
    func select(_ device: String) {}
}
struct CardButtonStyle {} // real one conforms to SwiftUI.ButtonStyle

// MARK: environment keys (Pulse-declared; the key-declaration pattern is itself SwiftUI API)
private struct BoolKey: EnvironmentKey { static let defaultValue = false }
private struct DoubleKey: EnvironmentKey { static let defaultValue = 0.0 }
private struct ColorKey: EnvironmentKey { static let defaultValue = Color.white }
private struct StyleKey: EnvironmentKey { static let defaultValue = ColorTransitionStyle.ramp }
private struct SurfaceKey: EnvironmentKey { static let defaultValue = NotchSurfaceStyle() }
extension EnvironmentValues {
    var codenotchReduceTransparency: Bool { get { self[BoolKey.self] } set { self[BoolKey.self] = newValue } }
    var usageWatchLimit: Double { get { self[DoubleKey.self] } set { self[DoubleKey.self] = newValue } }
    var usageCriticalLimit: Double { get { self[DoubleKey.self] } set { self[DoubleKey.self] = newValue } }
    var colorTransitionStyle: ColorTransitionStyle { get { self[StyleKey.self] } set { self[StyleKey.self] = newValue } }
    var codenotchAccentColor: Color { get { self[ColorKey.self] } set { self[ColorKey.self] = newValue } }
    var tooltipSecondaryInk: Color { get { self[ColorKey.self] } set { self[ColorKey.self] = newValue } }
    var notchSurfaceStyle: NotchSurfaceStyle { get { self[SurfaceKey.self] } set { self[SurfaceKey.self] = newValue } }
}
