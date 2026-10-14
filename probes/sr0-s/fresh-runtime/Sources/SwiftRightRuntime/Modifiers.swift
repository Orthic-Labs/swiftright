import Foundation

// Modifiers are wrapper views. Each one is a graph node whose lifecycle (appear, disappear,
// task, focus, environment override, animation comparison) follows the node's identity.
// Padding is the one modifier with geometry; the others pass their child's geometry through.

struct Modified<Content: View>: View, PrimitiveView {
    let content: Content
    let spec: ModifierSpec

    @MainActor public var body: Never { return fatalError("modifier has no body") }
    var nodeKind: NodeKind { .modifier(spec) }
    var nodeContent: (any View)? { content }
}

/// A modifier node built by the runtime itself (for example the per-row `onDelete` hook), when the wrapped view is
/// only available as an existential.
struct ModifierWrapper: View, PrimitiveView {
    let inner: any View
    let spec: ModifierSpec

    @MainActor public var body: Never { return fatalError("modifier has no body") }
    var nodeKind: NodeKind { .modifier(spec) }
    var nodeContent: (any View)? { inner }
}

extension ModifierWrapper: @MainActor WrappedModifier {
    var modifierInner: any View { inner }
    var modifierSpec: ModifierSpec { spec }
}

extension View {
    /// Insets all edges by a fixed length.
    public func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
    }

    /// Proposes fixed dimensions to this view's content, then aligns content in the resulting frame.
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        Modified(content: self, spec: .frame(FrameSpec(width: width, height: height, alignment: alignment)))
    }

    /// Offers size within the given bounds on each axis and aligns the content in the resulting frame.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)
    public func frame(
        minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        Modified(content: self, spec: .flexibleFrame(FlexibleFrameSpec(
            minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
            minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight, alignment: alignment
        )))
    }

    /// Insets the view by `length` on the given edges. A nil length uses the fixed default of 16 pt.
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        Modified(content: self, spec: .padding(EdgeInsets(edges, length ?? defaultPaddingLength)))
    }

    /// Insets the view by the given amount on each edge. Apple: https://developer.apple.com/documentation/swiftui/view/padding(_:)-6pgl9
    public func padding(_ insets: EdgeInsets) -> some View {
        Modified(content: self, spec: .padding(insets))
    }

    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        Modified(content: self, spec: .appear(action ?? {}))
    }

    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        Modified(content: self, spec: .disappear(action ?? {}))
    }

    /// Starts on appear. Cancelled on disappear, and on any change of this node's identity
    /// (for example a ForEach row whose id changes). Results are committed through
    /// `TaskOwner.current?.commit { ... }`, which rejects stale generations.
    public func task(
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        Modified(content: self, spec: .task(priority, nil, action))
    }

    /// As SwiftUI `task(id:)`: starts on appear, and cancels and restarts when `value` changes. The
    /// previous run's commits are rejected once it has been replaced.
    public func task<T: Equatable>(
        id value: T,
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        Modified(content: self, spec: .task(priority, AnyEquatable(value), action))
    }

    /// Gives focus to this view while `binding` names `value`. Removing the view clears the focus
    /// (when it names `value`), as on the Mac oracle.
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View {
        let link = FocusLink(
            storage: ObjectIdentifier(binding.cell.resolved),
            isFocused: { binding.wrappedValue == value },
            focus: { binding.assign(value) },
            release: { if binding.wrappedValue == value { binding.reset() } }
        )
        return Modified(content: self, spec: .focus(link))
    }

    /// Gives focus to this view while `condition` is true: `.focused(_:equals: true)` of a `Bool` focus state. Apple: https://developer.apple.com/documentation/swiftui/view/focused(_:)
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        focused(condition, equals: true)
    }

    /// Multiplies this view's opacity. Changes animate under an animated transaction.
    public func opacity(_ value: Double) -> some View {
        Modified(content: self, spec: .opacity(value))
    }

    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        Modified(content: self, spec: .animation(AnyEquatable(value), animation))
    }

    /// As SwiftUI `onChange(of:initial:_:)`: runs `action(oldValue, newValue)` when an evaluation of this view sees a `value`
    /// that differs from the one the previous evaluation saw. With `initial` the first evaluation also runs it, with the same
    /// value as both arguments. The previous value is part of the view's retained state: inside a `List`, a row that is
    /// removed and reinserted with the same identity keeps it with its `@State`, so the action also runs once on reinsertion
    /// when the value changed in between. A `VStack` / `LazyVStack` row starts over and only records the value.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        Modified(content: self, spec: .onChange(AnyEquatable(value), initial, { old, new in
            guard let old = old as? V, let new = new as? V else { return }
            action(old, new)
        }))
    }

    /// `onChange(of:initial:_:)` whose action takes no arguments (the SwiftUI overload of the same name).
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        Modified(content: self, spec: .onChange(AnyEquatable(value), initial, { _, _ in action() }))
    }

    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment[keyPath: keyPath] = value
        }))
    }

    /// Adds a value to the upward preference stream for `key`.
    public func preference<Key: PreferenceKey>(key: Key.Type, value: Key.Value) -> some View {
        Modified(content: self, spec: .preference(PreferenceContribution(value, for: key)))
    }

    /// Runs after the graph settles when the reduced preference value changes from its prior value.
    public func onPreferenceChange<Key: PreferenceKey>(
        _ key: Key.Type,
        perform action: @escaping (Key.Value) -> Void
    ) -> some View where Key.Value: Equatable {
        Modified(content: self, spec: .onPreferenceChange(PreferenceObserver(key, action: action)))
    }

    // MARK: SR1 modifiers

    /// Selection value of a row in a `List(selection:)`. Apple: https://developer.apple.com/documentation/swiftui/view/tag(_:)
    public func tag<V: Hashable>(_ tag: V) -> some View {
        Modified(content: self, spec: .tag(AnyHashable(tag)))
    }

    /// Shows or hides the separator under this List row. Apple: https://developer.apple.com/documentation/swiftui/view/listrowseparator(_:edges:)
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        Modified(content: self, spec: .listRowSeparator(visibility))
    }

    /// Replaces the background of this List row; a Color or a Rectangle filled with a Color is drawn, another view is reported unsupported by the host.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/listrowbackground(_:)
    public func listRowBackground<V: View>(_ view: V?) -> some View {
        var style = ListRowStyle(setsBackground: true)
        if let view {
            if let color = view as? Color { style.background = color.resolvedColor }
            else if let primitive = view as? PrimitiveView, case .shape(let shape) = primitive.nodeKind, shape.geometry == .rectangle, shape.paint?.kind == .fill { style.background = shape.paint?.color }
            else { style.backgroundUnsupported = true }
        }
        return Modified(content: self, spec: .listRowBackground(ListRowBackground(style: style)))
    }

    /// Overrides the accessibility label of this view. Apple: https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)
    public func accessibilityLabel(_ label: String) -> some View {
        Modified(content: self, spec: .accessibilityLabel(label))
    }

    /// Records selected Toggle style metadata. Headless rendering behavior is unchanged.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        Modified(content: self, spec: .environment({ environment in
            environment.toggleStyleMetadata = String(describing: S.self)
        }))
    }

    /// Selects the style of the Buttons in this view. Apple: https://developer.apple.com/documentation/swiftui/view/buttonstyle(_:)
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        Modified(content: self, spec: .environment({ environment in
            environment.buttonStyleMetadata = String(describing: S.self)
        }))
    }

    /// Selects the style of the Lists in this view. Apple: https://developer.apple.com/documentation/swiftui/view/liststyle(_:)
    public func listStyle<S: ListStyle>(_ style: S) -> some View {
        Modified(content: self, spec: .environment({ environment in
            environment.listStyleMetadata = String(describing: S.self)
        }))
    }

    /// Hides control labels from resolved content while preserving their accessibility titles.
    public func labelsHidden() -> some View {
        Modified(content: self, spec: .environment({ environment in
            environment.labelsHidden = true
        }))
    }

    /// Registers a keyboard shortcut for the button inside this view. `modifiers` defaults to `.command`, the
    /// platform's primary modifier. Apple: https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        Modified(content: self, spec: .keyboardShortcut(key, modifiers))
    }

    /// Registers a keyboard shortcut for the button inside this view. Apple: https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:)
    /// `.defaultAction` (Return) also makes the button the default button, which macOS draws as the prominent push button.
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        Modified(content: self, spec: .keyboardShortcut(shortcut.key, shortcut.modifiers))
    }

    /// Disables controls in this view. Nested `disabled(false)` does not re-enable a disabled ancestor.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/disabled(_:)
    public func disabled(_ disabled: Bool) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.isEnabled = environment.isEnabled && !disabled
        }))
    }

    /// Font of the text in this view. Apple: https://developer.apple.com/documentation/swiftui/view/font(_:)
    public func font(_ font: Font?) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.font = font
        }))
    }

    /// Displays descendant Text views in upper or lower case (the case of the displayed string, the layout and the accessibility label all follow); nil leaves them as written.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/textcase(_:)
    public func textCase(_ textCase: Text.Case?) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.textCase = textCase
        }))
    }

    /// Limits descendant Text views to at most `number` lines; nil removes the limit.
    public func lineLimit(_ number: Int?) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.lineLimit = number
        }))
    }

    /// Foreground colour of the content. Apple: https://developer.apple.com/documentation/swiftui/view/foregroundstyle(_:)
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        let color = style.resolvedColor
        return Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.foregroundStyle = color
        }))
    }
}
