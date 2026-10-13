import Foundation
// Explicit provider requirements, never expected pixels or native substitutions.
enum FactoryNativeProviderRequirement: String, CaseIterable {
    case sfSymbolProvider, centeredContinuousRoundedStroke, roundedFontProvider
    case lineLimitShaping, nativeSwitchPainting
}
func factoryProviderHold(_ requirements: [FactoryNativeProviderRequirement]) -> String? {
    guard !requirements.isEmpty else { return nil }
    return requirements.map { $0.rawValue }.sorted().joined(separator: ";")
}
