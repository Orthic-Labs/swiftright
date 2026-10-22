import Foundation

// Issue #82 (SR2 S2): contentShape and help.
//   - Pointer hits in this runtime are decided by a node's frame (Gestures.hitFrame), which is a superset of what SwiftUI hits by default (opaque content), so
//     `contentShape(Rectangle())` -- the common use, making a padded or clear area tappable -- needs no extra model and is the default here. A shape other than a rectangle
//     is accepted and the hit area stays the frame (not narrowed to the shape).
//   - `help` is a tooltip: Windows has no tooltip surface in the bridge yet, so the text is accepted and not shown; it never changes layout, painting or hit testing.

/// Apple: https://developer.apple.com/documentation/swiftui/contentshapekinds
public struct ContentShapeKinds: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let interaction = ContentShapeKinds(rawValue: 1)
    public static let dragPreview = ContentShapeKinds(rawValue: 2)
    public static let contextMenuPreview = ContentShapeKinds(rawValue: 4)
    public static let hoverEffect = ContentShapeKinds(rawValue: 8)
    public static let focusEffect = ContentShapeKinds(rawValue: 16)
    public static let accessibility = ContentShapeKinds(rawValue: 32)
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/contentshape(_:eofill:)
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/contentshape(_:_:eofill:)
    public func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/help(_:)-4k2k8
    public func help(_ text: Text) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/help(_:)-7l7bk
    public func help<S: StringProtocol>(_ text: S) -> some View { self }
}
