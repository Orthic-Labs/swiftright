import Foundation

/// Scanline order supplied by a native glyph provider.
public enum SystemImageRasterRowOrder: String, Hashable, Sendable {
    case topDown
    case bottomUp
}

/// Bounded native coverage input for an image provider.
public struct SystemImageRasterInput: Sendable {
    public let sourceWidth: UInt32
    public let sourceHeight: UInt32
    public let rowBytes: UInt32
    public let coverage: [UInt8]
    public let coverageMaximum: UInt8
    public let rowOrder: SystemImageRasterRowOrder
    public let selectedFace: String
    public let expectedFace: String

    public init(sourceWidth: UInt32,
                sourceHeight: UInt32,
                rowBytes: UInt32,
                coverage: [UInt8],
                coverageMaximum: UInt8,
                rowOrder: SystemImageRasterRowOrder,
                selectedFace: String,
                expectedFace: String) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.rowBytes = rowBytes
        self.coverage = coverage
        self.coverageMaximum = coverageMaximum
        self.rowOrder = rowOrder
        self.selectedFace = selectedFace
        self.expectedFace = expectedFace
    }
}

public struct SystemImageRasterOutput: Equatable, Sendable {
    public let rgba: [UInt8]
    public let width: UInt32
    public let height: UInt32
    public let renderedWidth: UInt32
    public let renderedHeight: UInt32
    public let nonZeroCoverage: UInt32
    public let maxCoverage: UInt8

    public init(rgba: [UInt8],
                width: UInt32,
                height: UInt32,
                renderedWidth: UInt32,
                renderedHeight: UInt32,
                nonZeroCoverage: UInt32,
                maxCoverage: UInt8) {
        self.rgba = rgba
        self.width = width
        self.height = height
        self.renderedWidth = renderedWidth
        self.renderedHeight = renderedHeight
        self.nonZeroCoverage = nonZeroCoverage
        self.maxCoverage = maxCoverage
    }
}

public enum SystemImageRasterError: Error, Equatable, Sendable {
    case invalidDimensions
    case invalidCoverage
    case selectedFaceMismatch
    case emptyCoverage
    case targetTooLarge
}

/// Converts native grayscale coverage into bounded RGBA while preserving
/// provider identity, scanline direction & aspect-fit geometry.
public enum SystemImageRasterProvider {
    private static let maxDimension: UInt32 = 4096
    private static let maxRGBABytes: UInt64 = 16 * 1024 * 1024

    public static func compose(_ input: SystemImageRasterInput,
                               targetWidth: UInt32,
                               targetHeight: UInt32,
                               tintRGBA: UInt32,
                               aspectFit: Bool = true) throws -> SystemImageRasterOutput {
        guard input.sourceWidth > 0, input.sourceHeight > 0,
              input.rowBytes >= input.sourceWidth,
              input.coverageMaximum > 0,
              targetWidth > 0, targetHeight > 0 else {
            throw SystemImageRasterError.invalidDimensions
        }
        guard input.sourceWidth <= maxDimension, input.sourceHeight <= maxDimension,
              targetWidth <= maxDimension, targetHeight <= maxDimension else {
            throw SystemImageRasterError.targetTooLarge
        }

        let sourceBytes = UInt64(input.rowBytes) * UInt64(input.sourceHeight)
        let targetBytes = UInt64(targetWidth) * UInt64(targetHeight) * 4
        guard sourceBytes <= maxRGBABytes,
              sourceBytes <= UInt64(input.coverage.count), targetBytes <= maxRGBABytes else {
            throw SystemImageRasterError.invalidCoverage
        }
        guard exactFace(input.selectedFace) == exactFace(input.expectedFace),
              !exactFace(input.expectedFace).isEmpty else {
            throw SystemImageRasterError.selectedFaceMismatch
        }
        guard input.coverage[0..<Int(sourceBytes)].contains(where: { $0 > 0 }) else {
            throw SystemImageRasterError.emptyCoverage
        }

        let fitted = fittedSize(sourceWidth: input.sourceWidth,
                                sourceHeight: input.sourceHeight,
                                targetWidth: targetWidth,
                                targetHeight: targetHeight,
                                aspectFit: aspectFit)
        let offsetX = (targetWidth - fitted.width) / 2
        let offsetY = (targetHeight - fitted.height) / 2
        var rgba = [UInt8](repeating: 0, count: Int(targetBytes))
        let red = UInt8((tintRGBA >> 24) & 0xff)
        let green = UInt8((tintRGBA >> 16) & 0xff)
        let blue = UInt8((tintRGBA >> 8) & 0xff)
        let tintAlpha = UInt32(tintRGBA & 0xff)
        var nonZero: UInt32 = 0
        var maximum: UInt8 = 0

        for y in 0..<fitted.height {
            let sourceY = (UInt64(y) * UInt64(input.sourceHeight)) / UInt64(fitted.height)
            let orderedY = input.rowOrder == .topDown
                ? sourceY
                : UInt64(input.sourceHeight - 1) - sourceY
            for x in 0..<fitted.width {
                let sourceX = (UInt64(x) * UInt64(input.sourceWidth)) / UInt64(fitted.width)
                let sourceIndex = Int(orderedY * UInt64(input.rowBytes) + sourceX)
                let sample = min(UInt32(input.coverage[sourceIndex]), UInt32(input.coverageMaximum))
                let coverage = UInt8((sample * 255 + UInt32(input.coverageMaximum) / 2) /
                                     UInt32(input.coverageMaximum))
                guard coverage > 0 else { continue }
                nonZero += 1
                maximum = max(maximum, coverage)
                let targetIndex = (Int(offsetY + y) * Int(targetWidth) + Int(offsetX + x)) * 4
                rgba[targetIndex] = red
                rgba[targetIndex + 1] = green
                rgba[targetIndex + 2] = blue
                rgba[targetIndex + 3] = UInt8((UInt32(coverage) * tintAlpha + 127) / 255)
            }
        }
        guard nonZero > 0 else { throw SystemImageRasterError.emptyCoverage }
        return SystemImageRasterOutput(rgba: rgba, width: targetWidth, height: targetHeight,
                                       renderedWidth: fitted.width, renderedHeight: fitted.height,
                                       nonZeroCoverage: nonZero, maxCoverage: maximum)
    }

    private static func exactFace(_ value: String) -> String {
        guard let end = value.firstIndex(of: "\0") else { return value }
        return String(value[..<end])
    }

    private static func fittedSize(sourceWidth: UInt32,
                                   sourceHeight: UInt32,
                                   targetWidth: UInt32,
                                   targetHeight: UInt32,
                                   aspectFit: Bool) -> (width: UInt32, height: UInt32) {
        guard aspectFit else { return (targetWidth, targetHeight) }
        let scale = min(Double(targetWidth) / Double(sourceWidth),
                        Double(targetHeight) / Double(sourceHeight))
        return (max(1, UInt32((Double(sourceWidth) * scale).rounded(.down))),
                max(1, UInt32((Double(sourceHeight) * scale).rounded(.down))))
    }
}
