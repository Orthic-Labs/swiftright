import Foundation
import Observation

// Issue #60 pass 3 (E9): `.environment(_ object:)` and `@Environment(Model.self)` for an @Observable class (SwiftUI 17 / macOS 14).
//
// SwiftUI semantics: `.environment(model)` puts the object in the environment of the view and everything below it, keyed by its TYPE (a nearer `.environment(other)` of the
// same type wins; `.environment(nil as Model?)` removes it); `@Environment(Model.self) var model` reads it, and a missing object is a programmer error (SwiftUI traps with
// "No Observable object of type Model found"). The read happens in the reader's body, so observation tracking sees the properties the body reads: a change to one re-evaluates
// the reader, as for an object held in @State.

/// The slot of an object of type `T`: one key per type, so two types never share a slot.
private enum ObservableObjectKey<T: AnyObject>: EnvironmentKey {
    static var defaultValue: T? { nil }
}

extension EnvironmentValues {
    /// The Observable object of type `T` in effect, nil when none is (`.environment(_:)` sets it).
    func observableObject<T: AnyObject>(_ type: T.Type) -> T? {
        self[ObservableObjectKey<T>.self]
    }

    mutating func setObservableObject<T: AnyObject>(_ object: T?) {
        self[ObservableObjectKey<T>.self] = object
    }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/environment(_:)-6h3ni (the Observable object form)
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.setObservableObject(object)
        }))
    }
}

extension Environment {
    /// `@Environment(Model.self) var model`. Apple: https://developer.apple.com/documentation/swiftui/environment/init(_:)-8slkf
    public init(_ objectType: Value.Type) where Value: AnyObject & Observable {
        self.init(reading: { environment in
            guard let object = environment.observableObject(objectType) else {
                fatalError("No Observable object of type \(objectType) found. A View.environment(_:) for \(objectType) may be missing as an ancestor of this view.")
            }
            return object
        })
    }
}
