import SwiftRightRuntime

/// Thin host adapter over runtime-owned live Windows body-font policy.
/// Existing NativeMeasurer fields remain unchanged; only policy ownership moves.
typealias FactoryDefaultBodyFontPolicy = NativeWindowsBodyFont
typealias FactoryDefaultBodyFontError = NativeWindowsBodyFontError

func factoryDefaultBodyFontPolicy(dpi: UInt32) throws -> FactoryDefaultBodyFontPolicy {
    try NativeWindowsBodyFontResolver.resolve(dpi: dpi)
}
