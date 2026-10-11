import Foundation
// Compile with EXACT packaged FactoryProviderPolicy.swift on internal scratch only.
precondition(factoryProviderHold([]) == nil)
for requirement in FactoryNativeProviderRequirement.allCases {
    precondition(factoryProviderHold([requirement]) == requirement.rawValue)
}
precondition(factoryProviderHold([.lineLimitShaping, .roundedFontProvider]) == "lineLimitShaping;roundedFontProvider")
precondition(FactoryNativeProviderRequirement(rawValue: "inventedProvider") == nil)
print("{\"kind\":\"pure-provider-hold-controls\",\"synthetic\":true,\"nativeRuns\":0,\"positiveEmpty\":1,\"heldRequirements\":5,\"unknownRejected\":true}")
