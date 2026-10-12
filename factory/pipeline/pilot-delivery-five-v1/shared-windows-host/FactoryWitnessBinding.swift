// Tiny per-witness binding metadata. It does not alter Witness.swift or Graph input.
struct FactorySharedWitnessBinding: Equatable {
    let witnessType: String
    let caseID: String
    let expectedChildCount: Int?
}

enum FactorySharedWitnessBindings {
    static let stackOverlay = FactorySharedWitnessBinding(
        witnessType: "Witness_stack_overlay",
        caseID: "swiftui.stack-overlay.recipe/case/aac89c30fbc61515",
        expectedChildCount: nil)
    static let customLayoutTwoChild = FactorySharedWitnessBinding(
        witnessType: "Witness_custom_layout",
        caseID: "swiftui.custom-layout.recipe/case/6ed908118b5337e95",
        expectedChildCount: 2)
    static let customLayoutOneChild = FactorySharedWitnessBinding(
        witnessType: "Witness_custom_layout",
        caseID: "swiftui.custom-layout.recipe/case/b30ed0b185e8cb29",
        expectedChildCount: 1)
}
