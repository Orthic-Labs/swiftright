// SR1 round 4, block swiftui.observation: a parent that re-evaluates builds its children's view values again. SwiftUI does not run the body of a child whose inputs
// compare equal to the last ones (measured on macOS 27: appending to a model's array re-runs the list that reads it but not the rows it already shows, whose bodies
// read a plain global that changed). The runtime now skips such a body too. "Equal" is conservative: a stored property that cannot be compared (a closure, a
// Binding) makes the view different, so the body runs; dynamic properties (@State, @FocusState, @Environment) are bound to the node, not to the view value, and the
// environment the child inherits is compared separately (`Node.inheritedStamp`).

@MainActor
enum ViewEquality {
    static func equal(_ a: any View, _ b: any View) -> Bool {
        guard type(of: a) == type(of: b) else { return false }
        return childrenEqual(a, b, depth: 0)
    }

    private static func childrenEqual(_ a: Any, _ b: Any, depth: Int) -> Bool {
        if depth > 6 { return false }
        let ma = Mirror(reflecting: a), mb = Mirror(reflecting: b)
        let ca = Array(ma.children), cb = Array(mb.children)
        guard ca.count == cb.count else { return false }
        for index in ca.indices {
            if ca[index].label != cb[index].label { return false }
            if !fieldEqual(ca[index].value, cb[index].value, depth: depth + 1) { return false }
        }
        return true
    }

    private static func fieldEqual(_ x: Any, _ y: Any, depth: Int) -> Bool {
        if x is DynamicPropertyStorage { return type(of: x) == type(of: y) }
        let tx = type(of: x)
        guard tx == type(of: y) else { return false }
        if tx is AnyClass { return (x as AnyObject) === (y as AnyObject) }
        if let e = x as? any Equatable { return isEqual(e, y) }
        if String(describing: tx).contains("->") { return false }   // a closure
        let style = Mirror(reflecting: x).displayStyle
        switch style {
        case .struct, .tuple, .optional, .enum: return childrenEqual(x, y, depth: depth)
        default: return false
        }
    }

    private static func isEqual<T: Equatable>(_ x: T, _ y: Any) -> Bool {
        guard let other = y as? T else { return false }
        return x == other
    }
}
