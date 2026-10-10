import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A size proposal from parent to child. Each axis is nil (unspecified), finite, or infinite.
public struct ProposedViewSize: Hashable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    public init(_ size: LayoutSize) {
        self.init(width: size.width, height: size.height)
    }

    @_disfavoredOverload
    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public static let zero = ProposedViewSize(width: 0, height: 0)
    public static let infinity = ProposedViewSize(width: CGFloat.infinity, height: CGFloat.infinity)
}

/// Portable geometry value types. Foundation's CGSize, CGPoint and CGRect are not Equatable or
/// complete on every toolchain this runtime builds on, so the runtime defines its own.
public struct LayoutPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    public static let zero = LayoutPoint(x: 0, y: 0)
}

public struct LayoutSize: Hashable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    @_disfavoredOverload
    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }

    public static let zero = LayoutSize(width: 0, height: 0)
}

public struct LayoutRect: Hashable, Sendable {
    public var origin: LayoutPoint
    public var size: LayoutSize

    public init(origin: LayoutPoint, size: LayoutSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: width, height: height))
    }

    @_disfavoredOverload
    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }

    public static let zero = LayoutRect(origin: .zero, size: .zero)

    public var minX: CGFloat { origin.x }
    public var minY: CGFloat { origin.y }
    public var maxX: CGFloat { origin.x + size.width }
    public var maxY: CGFloat { origin.y + size.height }
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
}

/// A finite proposed length. Nil and infinite proposals both mean "ideal" to a measuring node.
func finiteLength(_ value: CGFloat?) -> CGFloat? {
    guard let value, value.isFinite else { return nil }
    return value
}

public struct EdgeInsets: Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ edges: Edge.Set, _ length: CGFloat) {
        self.init(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0
        )
    }

    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }
}

public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

struct FrameSpec: Equatable {
    let width: CGFloat?
    let height: CGFloat?
    let alignment: Alignment
}

/// Flexible frame bounds, separate from legacy fixed dimensions.
/// The headless runtime clamps negative/NaN minima to zero, treats a NaN maximum as zero,
/// preserves positive infinity, and raises a maximum below the minimum to the minimum.
/// This keeps malformed inputs finite without asserting native SDK parity for those inputs.
struct FlexibleFrameSpec: Equatable {
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    init(minWidth: CGFloat?, maxWidth: CGFloat?, minHeight: CGFloat?, maxHeight: CGFloat?, alignment: Alignment) {
        self.minWidth = Self.normalizedMinimum(minWidth)
        self.maxWidth = Self.normalizedMaximum(maxWidth, minimum: self.minWidth)
        self.minHeight = Self.normalizedMinimum(minHeight)
        self.maxHeight = Self.normalizedMaximum(maxHeight, minimum: self.minHeight)
        self.alignment = alignment
    }

    func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(
            width: childDimension(proposal.width, minimum: minWidth, maximum: maxWidth),
            height: childDimension(proposal.height, minimum: minHeight, maximum: maxHeight)
        )
    }

    func frameSize(for child: LayoutSize, proposal: ProposedViewSize) -> LayoutSize {
        LayoutSize(
            width: frameDimension(child.width, offered: proposal.width, minimum: minWidth, maximum: maxWidth),
            height: frameDimension(child.height, offered: proposal.height, minimum: minHeight, maximum: maxHeight)
        )
    }

    private func bounds(minimum: CGFloat?, maximum: CGFloat?) -> (minimum: CGFloat, maximum: CGFloat) {
        (minimum ?? 0, maximum ?? .infinity)
    }

    private static func normalizedMinimum(_ value: CGFloat?) -> CGFloat? {
        guard let value else { return nil }
        return max(0, finiteLength(value) ?? 0)
    }

    private static func normalizedMaximum(_ value: CGFloat?, minimum: CGFloat?) -> CGFloat? {
        guard let value else { return nil }
        let normalized = value.isNaN ? CGFloat.zero : max(0, value)
        return max(minimum ?? 0, normalized)
    }

    private func childDimension(_ offered: CGFloat?, minimum: CGFloat?, maximum: CGFloat?) -> CGFloat? {
        guard minimum != nil || maximum != nil else { return offered }
        let limits = bounds(minimum: minimum, maximum: maximum)
        guard let offered = finiteLength(offered) else {
            return limits.minimum > 0 ? limits.minimum : nil
        }
        return min(max(offered, limits.minimum), limits.maximum)
    }

    private func frameDimension(_ child: CGFloat, offered: CGFloat?, minimum: CGFloat?, maximum: CGFloat?) -> CGFloat {
        guard minimum != nil || maximum != nil else { return child }
        let limits = bounds(minimum: minimum, maximum: maximum)
        let target = finiteLength(offered) ?? child
        return min(max(target, limits.minimum), limits.maximum)
    }
}

/// A frame in physical device pixels.
public struct PixelRect: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

/// Rounds each edge of a logical rect to the physical pixel grid. Adjacent frames share edges,
/// so rounding is applied to edges, not to origin and size independently.
func snapToPixelGrid(_ rect: LayoutRect, scale: CGFloat) -> LayoutRect {
    let minX = (rect.minX * scale).rounded() / scale
    let minY = (rect.minY * scale).rounded() / scale
    let maxX = (rect.maxX * scale).rounded() / scale
    let maxY = (rect.maxY * scale).rounded() / scale
    return LayoutRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

func pixelRect(_ rect: LayoutRect, scale: CGFloat) -> PixelRect {
    let x0 = Int((rect.minX * scale).rounded())
    let y0 = Int((rect.minY * scale).rounded())
    let x1 = Int((rect.maxX * scale).rounded())
    let y1 = Int((rect.maxY * scale).rounded())
    return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}
