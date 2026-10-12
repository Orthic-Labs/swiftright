import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Source adapter for a provider that has registered exact bundled bytes.
/// It never supplies a fallback family or invented line height.
struct FactoryBundledFontResource: Sendable {
    let requestedFamily: String
    let providerFamily: String
    let postScriptName: String
    let resourceSHA256: String
    let path: String
}

struct FactoryBundledFontMetrics: Sendable {
    let lineHeightDIP: Float
    let ascentDIP: Float
    let descentDIP: Float
}

enum FactoryBundledFontAdapterError: Error {
    case customMetadataRequired
    case familyMismatch
    case providerResourceUnavailable
    case lineHeightUnavailable
}

/// Provider callback must verify resourceSHA256 against bytes before returning metrics.
typealias FactoryBundledFontResolver =
    (_ resource: FactoryBundledFontResource, _ metadata: Font.Metadata) throws -> FactoryBundledFontMetrics

func factoryBundledMeasureRequest(
    _ request: TextMeasureRequest,
    resource: FactoryBundledFontResource,
    resolve: FactoryBundledFontResolver,
    scale: Float
) throws -> (request: MeasureRequest, metrics: FactoryBundledFontMetrics) {
    guard let metadata = request.fontMetadata, metadata.isCustom,
          let family = metadata.familyName, let pointSize = metadata.pointSize else {
        throw FactoryBundledFontAdapterError.customMetadataRequired
    }
    guard family == resource.requestedFamily,
          pointSize.isFinite, pointSize > 0, pointSize <= 512 else {
        throw FactoryBundledFontAdapterError.familyMismatch
    }
    let weight = metadata.weight ?? .regular
    let metrics = try resolve(resource, metadata)
    guard metrics.lineHeightDIP.isFinite, metrics.lineHeightDIP > 0 else {
        throw FactoryBundledFontAdapterError.lineHeightUnavailable
    }
    let weightValue: UInt32
    switch weight {
    case .regular: weightValue = 400
    case .medium: weightValue = 500
    case .semibold: weightValue = 600
    case .bold: weightValue = 700
    }
    let bridgeRequest = MeasureRequest(
        text: request.text,
        fontFamily: resource.providerFamily,
        weight: weightValue,
        fontSize: Float(pointSize),
        lineHeight: metrics.lineHeightDIP,
        scale: scale,
        maxWidth: Float(request.proposedWidth ?? 0) * scale
    )
    return (bridgeRequest, metrics)
}
