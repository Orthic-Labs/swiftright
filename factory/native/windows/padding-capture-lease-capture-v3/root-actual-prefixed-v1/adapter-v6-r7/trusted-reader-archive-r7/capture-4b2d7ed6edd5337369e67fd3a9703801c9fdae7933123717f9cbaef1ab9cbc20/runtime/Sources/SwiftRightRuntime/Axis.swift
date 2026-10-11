import Foundation

/// An axis in a two-dimensional coordinate system.
public enum Axis: Sendable, CaseIterable, Equatable {
    case horizontal
    case vertical

    /// A set of axes represented as a compact bit field.
    public struct Set: OptionSet, Sendable {
        public typealias Element = Self

        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)

        public let rawValue: UInt8

        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public func contains(_ axis: Axis) -> Bool {
            let bit = axis == .horizontal ? Self.horizontal.rawValue : Self.vertical.rawValue
            return rawValue & bit != 0
        }
    }
}
