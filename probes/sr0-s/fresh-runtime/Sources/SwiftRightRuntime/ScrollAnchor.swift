import Foundation

extension View {
    /// The initial scroll position of scroll views in this view: the content point at `anchor` of the content meets the same point of the
    /// viewport (`.bottom` starts at the end). It applies until the offset is set programmatically.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:)
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.defaultScrollAnchor = anchor
        }))
    }
}
