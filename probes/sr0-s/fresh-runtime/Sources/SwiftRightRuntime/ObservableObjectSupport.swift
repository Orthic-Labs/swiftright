import Foundation
import Combine   // Apple's on macOS; SwiftRightCombine (OpenCombine-backed) on Windows and Linux (#88)

// Issue #88: the ObservableObject family, so SwiftUI code written with Combine runs as written.
//   - @StateObject: the object is made once per view identity (the autoclosure runs on the first evaluation only) and lives with the node.
//   - @ObservedObject: the object the parent passes; the view follows whichever object it currently holds.
//   - @EnvironmentObject / .environmentObject(_:): an object put in the environment by type; reading a missing one traps, as SwiftUI does.
//   - Each of them subscribes the view to the object's objectWillChange: a send marks the view for re-evaluation at the next flush, which runs after the
//     property has changed (objectWillChange fires before the write, as in SwiftUI). A send off the main thread is moved to the main actor.
//   - $object.property gives a Binding (ObservedObject.Wrapper, dynamic member lookup on reference-writable key paths).
//   - .onReceive(publisher) { value in ... }: subscribed once per view identity, delivered on the main actor; the latest closure runs.

/// Holds one view's subscription to one object's objectWillChange.
@MainActor
final class ObjectWillChangeLink {
    weak var node: Node?
    private(set) weak var object: AnyObject?
    private var cancellable: AnyCancellable?

    func follow<O: ObservableObject>(_ object: O, node: Node) {
        self.node = node
        guard self.object !== object else { return }
        self.object = object
        cancellable = object.objectWillChange.sink { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.fire() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.fire() } }
            }
        }
    }

    private func fire() {
        guard let node, let graph = node.owner else { return }
        graph.noteChange(node)
    }
}

@MainActor
final class StateObjectBox<O: ObservableObject> {
    var object: O?
    let link = ObjectWillChangeLink()
}

/// Apple: https://developer.apple.com/documentation/swiftui/stateobject
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicPropertyStorage {
    final class Cell { var box: AnyObject? }
    let make: () -> ObjectType
    let cell = Cell()

    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { make = thunk }

    @MainActor private var box: StateObjectBox<ObjectType> {
        if let b = cell.box as? StateObjectBox<ObjectType> { return b }
        let b = StateObjectBox<ObjectType>(); cell.box = b; return b
    }

    @MainActor public var wrappedValue: ObjectType {
        let b = box
        if let o = b.object { return o }
        let o = make(); b.object = o; return o
    }

    @MainActor public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(object: wrappedValue) }

    @MainActor func bindDynamicProperty(to node: Node, key: String) {
        let stored: StateObjectBox<ObjectType>
        if let existing = node.storage[key] as? StateObjectBox<ObjectType> { stored = existing } else { stored = box; node.storage[key] = stored }
        cell.box = stored
        if stored.object == nil { stored.object = make() }
        stored.link.follow(stored.object!, node: node)
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/observedobject
@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: DynamicPropertyStorage {
    /// Apple: https://developer.apple.com/documentation/swiftui/observedobject/wrapper
    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        @MainActor public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let object = object
            return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
        }
    }

    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public init(initialValue: ObjectType) { self.wrappedValue = initialValue }
    public var projectedValue: Wrapper { Wrapper(object: wrappedValue) }

    @MainActor func bindDynamicProperty(to node: Node, key: String) {
        let link = (node.storage[key] as? ObjectWillChangeLink) ?? ObjectWillChangeLink()
        node.storage[key] = link
        link.follow(wrappedValue, node: node)
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/environmentobject
@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicPropertyStorage {
    final class Cell { weak var node: Node? }
    let cell = Cell()
    public init() {}

    @MainActor public var wrappedValue: ObjectType {
        guard let object = cell.node?.environment.observableObject(ObjectType.self) else {
            fatalError("No ObservableObject of type \(ObjectType.self) found. A View.environmentObject(_:) for \(ObjectType.self) may be missing as an ancestor of this view.")
        }
        return object
    }

    @MainActor public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(object: wrappedValue) }

    @MainActor func bindDynamicProperty(to node: Node, key: String) {
        cell.node = node
        guard let object = node.environment.observableObject(ObjectType.self) else { return }
        let link = (node.storage[key] as? ObjectWillChangeLink) ?? ObjectWillChangeLink()
        node.storage[key] = link
        link.follow(object, node: node)
    }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/environmentobject(_:)
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.setObservableObject(object)
        }))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/onreceive(_:perform:)
    public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View where P.Failure == Never {
        OnReceiveView(content: self, publisher: publisher, action: action)
    }
}

final class OnReceiveBox: @unchecked Sendable {
    var cancellable: AnyCancellable?
    var action: ((Any) -> Void)?
}

@MainActor
struct OnReceiveBinder: DynamicPropertyStorage {
    final class Cell { var box = OnReceiveBox() }
    let cell = Cell()
    func bindDynamicProperty(to node: Node, key: String) {
        if let existing = node.storage[key] as? OnReceiveBox { cell.box = existing } else { node.storage[key] = cell.box }
    }
}

struct OnReceiveView<Content: View, P: Publisher>: View where P.Failure == Never {
    let content: Content
    let publisher: P
    let action: (P.Output) -> Void
    let binder = OnReceiveBinder()

    @MainActor var body: some View {
        let box = binder.cell.box
        let action = action
        box.action = { action($0 as! P.Output) }
        if box.cancellable == nil {
            box.cancellable = publisher.sink { [weak box] value in
                let carried = UncheckedSendable(value)
                let deliver: @Sendable () -> Void = { MainActor.assumeIsolated { box?.action?(carried.value) } }
                if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
            }
        }
        return content
    }
}

/// A value handed to the main actor from a publisher's thread (the publisher owns its thread safety, as in SwiftUI).
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
