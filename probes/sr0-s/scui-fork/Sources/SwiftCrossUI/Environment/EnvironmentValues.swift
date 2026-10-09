import Foundation

/// The environment used when constructing scenes and views. Each scene or view
/// gets to modify the environment before passing it on to its children, which
/// is the basis of many view modifiers.
public struct EnvironmentValues {
    /// A font resolution context derived from the current environment.
    ///
    /// Essentially just a subset of the environment.
    @MainActor
    public var fontResolutionContext: Font.Context {
        Font.Context(
            overlay: fontOverlay,
            deviceClass: backend.deviceClass,
            resolveTextStyle: { backend.resolveTextStyle($0) }
        )
    }

    /// The current font resolved to a form suitable for rendering.
    ///
    /// Just a helper method for our own backends. We haven't made this public
    /// because it would be weird to have two pretty equivalent ways of resolving
    /// fonts.
    @MainActor
    @_spi(Backends) public var resolvedFont: Font.Resolved {
        font.resolve(in: fontResolutionContext)
    }

    /// The suggested foreground color for backends to use.
    ///
    /// Backends don't neccessarily have to obey this when
    /// ``EnvironmentValues/foregroundColor`` is `nil`.
    public var suggestedForegroundColor: Color {
        foregroundColor ?? colorScheme.defaultForegroundColor
    }

    /// Called by view graph nodes when they resize due to an internal state
    /// change and end up changing size.
    ///
    /// Each view graph node sets its own handler when passing the environment
    /// on to its children, setting up a bottom-up update chain up which resize
    /// events can propagate.
    @_spi(Backends) public var onResize: @MainActor (_ newSize: ViewSize) -> Void

    /// Backing storage for extensible subscript
    private var values: [ObjectIdentifier: Any]

    /// An internal environment value used to control whether layout caching is
    /// enabled or not.
    ///
    /// This is set to `true` when computing non-final layouts. E.g. when a stack
    /// computes the minimum and maximum sizes of its children, it should enable
    /// layout caching because those updates are guaranteed to be non-final. The
    /// reason that we can't cache on non-final updates is that the last layout
    /// proposal received by each view must be its intended final proposal.
    var allowLayoutCaching: Bool = false

    /// Backing storage for observable subscript
    private var observableObjects: [ObjectIdentifier: any ObservableObject]


    /// Gets an environment value given an environment key's metatype.
    ///
    /// - Parameter key: The type of the key.
    /// - Returns: The environment value associated with `key`, or the key's
    ///   default value if it hasn't been set in the environment yet.
    public subscript<T: EnvironmentKey>(_ key: T.Type) -> T.Value {
        get {
            values[ObjectIdentifier(T.self), default: T.defaultValue] as! T.Value
        }
        set {
            values[ObjectIdentifier(T.self)] = newValue
        }
    }

    public subscript<T: ObservableObject>(observable key: T.Type) -> T? {
        get {
            guard let value = observableObjects[ObjectIdentifier(T.self)] as? T? else {
                let message =
                    "EnvironmentValues type mismatch: value for key '\(T.self).self' doesn't match expected type '\(T.self)'"
                logger.critical("\(message)")
                fatalError(message)
            }
            return value
        }
        set {
            observableObjects[ObjectIdentifier(T.self)] = newValue
        }
    }

    /// Brings the current window forward.
    ///
    /// This is not guaranteed to always bring the window to the top (due
    /// to focus stealing prevention).
    @MainActor
    func bringWindowForward() {
        func activate<Backend: BaseAppBackend>(with backend: Backend) {
            backend.activate(window: window as! Backend.Window)
        }
        activate(with: backend)
    }

    /// The backend in use.
    ///
    /// Mustn't change throughout the app's lifecycle.
    let backend: any BaseAppBackend

    /// Presents an 'Open file' dialog fit for selecting a single file.
    ///
    /// Displays as a modal for the current window, or the entire app if
    /// accessed outside of a scene's view graph (in which case the backend
    /// can decide whether to make it an app modal, a standalone window, or a
    /// modal for a window of its choosing).
    ///
    /// - Important: GtkBackend, Gtk3Backend, and WinUIBackend will only
    ///   enable _either_ files or directories for selection, but won't
    ///   enable both types in a single dialog.
    @MainActor
    @available(tvOS, unavailable, message: "tvOS does not provide file system access")
    public var chooseFile: PresentSingleFileOpenDialogAction {
        PresentSingleFileOpenDialogAction(
            backend: backend,
            window: MainActorBox(value: window)
        )
    }

    /// Presents a 'Save file' dialog fit for selecting a save destination.
    ///
    /// Displays as a modal for the current window, or the entire app if
    /// accessed outside of a scene's view graph (in which case the backend
    /// can decide whether to make it an app modal, a standalone window, or a
    /// window of its choosing).
    @MainActor
    public var chooseFileSaveDestination: PresentFileSaveDialogAction {
        PresentFileSaveDialogAction(
            backend: backend,
            window: MainActorBox(value: window)
        )
    }

    /// Presents an alert for the current window, or the entire app if accessed
    /// outside of a scene's view graph (in which case the backend can decide
    /// whether to make it an app modal, a standalone window, or a modal for a
    /// window of its choosing).
    @MainActor
    public var presentAlert: PresentAlertAction {
        PresentAlertAction(environment: self)
    }

    /// Opens a URL with the default application.
    ///
    /// May present an application picker if multiple applications are registered
    /// for the given URL protocol.
    ///
    /// `nil` on platforms that don't support opening external URLS (none at the
    /// moment).
    @MainActor
    public var openURL: OpenURLAction {
        OpenURLAction(backend: backend)
    }

    /// Opens a window with the specified ID.
    @MainActor
    public var openWindow: OpenWindowAction {
        OpenWindowAction(environment: self)
    }

    /// Closes the enclosing window.
    @MainActor
    public var dismissWindow: DismissWindowAction {
        DismissWindowAction(
            backend: backend,
            window: MainActorBox(value: window)
        )
    }

    /// Reveals a file in the system's file manager.
    ///
    /// This opens the file's enclosing directory and highlights the file.
    ///
    /// `nil` on platforms that don't support revealing files, e.g. iOS.
    @MainActor
    public var revealFile: RevealFileAction? {
        RevealFileAction(backend: backend)
    }

    /// Whether the backend can have multiple windows open at once. Mobile
    /// backends generally can't.
    @MainActor
    public var supportsMultipleWindows: Bool {
        backend.supportsMultipleWindows
    }

    /// The display styles supported by ``DatePicker``. ``datePickerStyle`` must be one of these.
    public let supportedDatePickerStyles: [DatePickerStyle]

    /// Checks whether a picker style is supported by the current backend.
    @MainActor
    public var isPickerStyleSupported: PickerSupportedAction {
        PickerSupportedAction(backend: backend)
    }

    /// Creates the default environment.
    ///
    /// - Parameters:
    ///   - backend: The app's backend.
    @_spi(Backends) public init<Backend: BaseAppBackend>(backend: Backend) {
        self.backend = backend

        onResize = { _ in }
        values = [:]
        observableObjects = [:]

        if let backend = backend as? any BackendFeatures.DatePickers {
            self.supportedDatePickerStyles = backend.supportedDatePickerStyles
        } else {
            self.supportedDatePickerStyles = [.automatic]
        }
    }

    /// Returns a copy of the environment with the specified property set to the
    /// provided new value.
    ///
    /// - Parameters:
    ///   - keyPath: A key path to the property to set.
    ///   - newValue: The new value of the property.
    /// - Returns: A copy of the environment with the specified property set to
    ///   `newValue`.
    public func with<T>(_ keyPath: WritableKeyPath<Self, T>, _ newValue: T) -> Self {
        var environment = self
        environment[keyPath: keyPath] = newValue
        return environment
    }
}

extension EnvironmentValues {
    /// The app storage provider to use for `@AppStorage` property wrappers.
    public var appStorageProvider: any AppStorageProvider {
        get { self[__Key_appStorageProvider.self] }
        set { self[__Key_appStorageProvider.self] = newValue }
    }
    struct __Key_appStorageProvider: EnvironmentKey { static var defaultValue: any AppStorageProvider { DefaultAppStorageProvider() } }

    /// The current stack orientation.
    ///
    /// Inherited by ``ForEach`` and ``Group`` so that they can be used without
    /// affecting layout.
    public var layoutOrientation: Orientation {
        get { self[__Key_layoutOrientation.self] }
        set { self[__Key_layoutOrientation.self] = newValue }
    }
    struct __Key_layoutOrientation: EnvironmentKey { static var defaultValue: Orientation { .vertical } }

    /// The current stack alignment.
    ///
    /// Inherited by ``ForEach`` and ``Group`` so that they can be used without
    /// affecting layout.
    public var layoutAlignment: StackAlignment {
        get { self[__Key_layoutAlignment.self] }
        set { self[__Key_layoutAlignment.self] = newValue }
    }
    struct __Key_layoutAlignment: EnvironmentKey { static var defaultValue: StackAlignment { .center } }

    /// Whether to use the ZStack StackLayout variants.
    public var usesZStackLayout: Bool {
        get { self[__Key_usesZStackLayout.self] }
        set { self[__Key_usesZStackLayout.self] = newValue }
    }
    struct __Key_usesZStackLayout: EnvironmentKey { static var defaultValue: Bool { false } }

    /// The alignment of content inside a ``ZStack``.
    /// Only gets used when ``usesZStackLayout`` is `true`.
    public var zStackContentAlignment: Alignment {
        get { self[__Key_zStackContentAlignment.self] }
        set { self[__Key_zStackContentAlignment.self] = newValue }
    }
    struct __Key_zStackContentAlignment: EnvironmentKey { static var defaultValue: Alignment { .center } }

    /// The current stack spacing.
    ///
    /// Inherited by ``ForEach`` and ``Group`` so that they can be used without
    /// affecting layout.
    public var layoutSpacing: Int {
        get { self[__Key_layoutSpacing.self] }
        set { self[__Key_layoutSpacing.self] = newValue }
    }
    struct __Key_layoutSpacing: EnvironmentKey { static var defaultValue: Int { 10 } }

    /// The current font.
    public var font: Font {
        get { self[__Key_font.self] }
        set { self[__Key_font.self] = newValue }
    }
    struct __Key_font: EnvironmentKey { static var defaultValue: Font { .body } }

    /// A font overlay storing font modifications.
    ///
    /// If these conflict with the font's internal overlay, these win out.
    ///
    /// We keep this separate overlay for modifiers because we want modifiers to
    /// be persisted even if the developer sets a custom font further down the
    /// view hierarchy.
    internal var fontOverlay: __Key_fontOverlay.Value {
        get { self[__Key_fontOverlay.self] }
        set { self[__Key_fontOverlay.self] = newValue }
    }
    struct __Key_fontOverlay: EnvironmentKey { static let defaultValue = Font.Overlay() }

    /// How lines should be aligned relative to each other when line wrapped.
    public var multilineTextAlignment: HorizontalAlignment {
        get { self[__Key_multilineTextAlignment.self] }
        set { self[__Key_multilineTextAlignment.self] = newValue }
    }
    struct __Key_multilineTextAlignment: EnvironmentKey { static var defaultValue: HorizontalAlignment { .leading } }

    /// Whether to override the case of displayed ``Text`` views.
    ///
    /// `nil` displays the text without any case changes.
    public var textCase: Text.Case? {
        get { self[__Key_textCase.self] }
        set { self[__Key_textCase.self] = newValue }
    }
    struct __Key_textCase: EnvironmentKey { static var defaultValue: Text.Case? { nil } }

    /// The current color scheme of the current view scope.
    public var colorScheme: ColorScheme {
        get { self[__Key_colorScheme.self] }
        set { self[__Key_colorScheme.self] = newValue }
    }
    struct __Key_colorScheme: EnvironmentKey { static var defaultValue: ColorScheme { .light } }

    /// The foreground color.
    ///
    /// `nil` means that the default foreground color of the current color scheme
    /// should be used.
    public var foregroundColor: Color? {
        get { self[__Key_foregroundColor.self] }
        set { self[__Key_foregroundColor.self] = newValue }
    }
    struct __Key_foregroundColor: EnvironmentKey { static var defaultValue: Color? { nil } }

    /// Called when a text field gets submitted (usually due to the user
    /// pressing Enter/Return).
    public var onSubmit: (@MainActor @Sendable () -> Void)? {
        get { self[__Key_onSubmit.self] }
        set { self[__Key_onSubmit.self] = newValue }
    }
    struct __Key_onSubmit: EnvironmentKey { static var defaultValue: (@MainActor @Sendable () -> Void)? { nil } }

    /// The scale factor of the current window.
    public var windowScaleFactor: Double {
        get { self[__Key_windowScaleFactor.self] }
        set { self[__Key_windowScaleFactor.self] = newValue }
    }
    struct __Key_windowScaleFactor: EnvironmentKey { static var defaultValue: Double { 1 } }

    /// The type of input that text fields represent.
    ///
    /// This affects autocomplete suggestions, and on devices with no physical keyboard, which
    /// on-screen keyboard to use.
    ///
    /// - Warning: Do not use this in place of validation, even if you only plan on supporting
    ///   mobile devices, as this does not restrict copy-paste and many mobile devices support
    ///   Bluetooth keyboards.
    public var textContentType: TextContentType {
        get { self[__Key_textContentType.self] }
        set { self[__Key_textContentType.self] = newValue }
    }
    struct __Key_textContentType: EnvironmentKey { static var defaultValue: TextContentType { .text } }

    /// The way that scrollable content interacts with the software keyboard.
    public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode {
        get { self[__Key_scrollDismissesKeyboardMode.self] }
        set { self[__Key_scrollDismissesKeyboardMode.self] = newValue }
    }
    struct __Key_scrollDismissesKeyboardMode: EnvironmentKey { static var defaultValue: ScrollDismissesKeyboardMode { .automatic } }

    /// The style of list to use.
    @_spi(Backends) public var listStyle: ListStyle {
        get { self[__Key_listStyle.self] }
        set { self[__Key_listStyle.self] = newValue }
    }
    struct __Key_listStyle: EnvironmentKey { static var defaultValue: ListStyle { .default } }

    /// The style of toggle to use.
    public var toggleStyle: ToggleStyle {
        get { self[__Key_toggleStyle.self] }
        set { self[__Key_toggleStyle.self] = newValue }
    }
    struct __Key_toggleStyle: EnvironmentKey { static var defaultValue: ToggleStyle { .button } }

    /// Whether the text should be selectable.
    ///
    /// Set by ``View/textSelectionEnabled(_:)``.
    public var isTextSelectionEnabled: Bool {
        get { self[__Key_isTextSelectionEnabled.self] }
        set { self[__Key_isTextSelectionEnabled.self] = newValue }
    }
    struct __Key_isTextSelectionEnabled: EnvironmentKey { static var defaultValue: Bool { false } }

    /// The resizing behaviour of windows.
    ///
    /// Set by ``Window/windowResizability(_:)->Scene``.
    internal var windowResizability: WindowResizability {
        get { self[__Key_windowResizability.self] }
        set { self[__Key_windowResizability.self] = newValue }
    }
    struct __Key_windowResizability: EnvironmentKey { static var defaultValue: WindowResizability { .automatic } }

    /// The default launch behavior of windows.
    ///
    /// Set by ``Window/defaultLaunchBehavior(_:)->Scene``.
    internal var defaultLaunchBehavior: SceneLaunchBehavior {
        get { self[__Key_defaultLaunchBehavior.self] }
        set { self[__Key_defaultLaunchBehavior.self] = newValue }
    }
    struct __Key_defaultLaunchBehavior: EnvironmentKey { static var defaultValue: SceneLaunchBehavior { .automatic } }

    /// The default size of windows.
    ///
    /// Defaults to 900x450.
    ///
    /// Set by ``Window/defaultSize(width:height:)->Scene``.
    internal var defaultWindowSize: SIMD2<Int> {
        get { self[__Key_defaultWindowSize.self] }
        set { self[__Key_defaultWindowSize.self] = newValue }
    }
    struct __Key_defaultWindowSize: EnvironmentKey { static var defaultValue: SIMD2<Int> { SIMD2(900, 450) } }

    /// The menu ordering to use.
    public var menuOrder: MenuOrder {
        get { self[__Key_menuOrder.self] }
        set { self[__Key_menuOrder.self] = newValue }
    }
    struct __Key_menuOrder: EnvironmentKey { static var defaultValue: MenuOrder { .automatic } }

    /// Backing store for ``EnvironmentValues/openWindowFunctionsByID``.
    /// Used to resolve "non-sendable type" warnings in Swift 5 and errors in Swift 6 language mode.
    private var openWindowFunctionsByIDStore: __Key_openWindowFunctionsByIDStore.Value {
        get { self[__Key_openWindowFunctionsByIDStore.self] }
        set { self[__Key_openWindowFunctionsByIDStore.self] = newValue }
    }
    struct __Key_openWindowFunctionsByIDStore: EnvironmentKey { static let defaultValue = UncheckedSendable(
        wrappedValue: Box<[String: @MainActor () -> Void]>([:])
    ) }

    /// A mapping of window IDs to functions that open the corresponding windows.
    internal var openWindowFunctionsByID: Box<[String: @MainActor () -> Void]> {
        get {
            openWindowFunctionsByIDStore.wrappedValue
        }
        set {
            openWindowFunctionsByIDStore.wrappedValue = newValue
        }
    }

    /// The app's lifecycle phase.
    ///
    /// Unlike in SwiftUI, where the app's lifecycle phase can only be accessed
    /// by using `@Environment(\.scenePhase)` directly on the ``App`` struct, this
    /// environment value can be accessed from anywhere within the application.
    public package(set) var appPhase: AppPhase {
        get { self[__Key_appPhase.self] }
        set { self[__Key_appPhase.self] = newValue }
    }
    struct __Key_appPhase: EnvironmentKey { static var defaultValue: AppPhase { .active } }

    /// The current scene's lifecycle phase.
    ///
    /// - Important: Unlike SwiftUI, this environment value cannot be accessed from
    ///   outside a scene. If you need to access the phase of the entire application,
    ///   use ``appPhase`` instead.
    public package(set) var scenePhase: ScenePhase {
        get {
            guard let phase = self[__Key_scenePhase.self] else {
                if window != nil {
                    // If there's a window but no scenePhase, we assume that the
                    // backend is actively trying to _set_ the scene phase; return
                    // a dummy value to prevent a crash.
                    return .inactive
                }

                fatalError(
                    """
                    'scenePhase' accessed from outside a scene (most likely \
                    with an @Environment property on the App struct); you \
                    probably meant to use 'appPhase' instead
                    """
                )
            }
            return phase
        }
        set { self[__Key_scenePhase.self] = newValue }
    }
    struct __Key_scenePhase: EnvironmentKey {
        static let defaultValue: ScenePhase? = nil
    }

    /// Backing store for ``EnvironmentValues/window``.
    /// Used to resolve "non-sendable type" warnings in Swift 5 and errors in Swift 6 language mode.
    private var windowStore: __Key_windowStore.Value {
        get { self[__Key_windowStore.self] }
        set { self[__Key_windowStore.self] = newValue }
    }
    struct __Key_windowStore: EnvironmentKey { static let defaultValue = UncheckedSendable<Any?>(wrappedValue: nil) }

    /// The backend's representation of the window that the current view is
    /// in, if any.
    ///
    /// This is a very internal detail that should never get exposed to users.
    @_spi(Backends) public var window: Any? {
        get {
            windowStore.wrappedValue
        }
        set {
            windowStore.wrappedValue = newValue
        }
    }

    /// Backing store for ``EnvironmentValues/sheet``.
    /// Used to resolve "non-sendable type" warnings in Swift 5 and errors in Swift 6 language mode.
    private var sheetStore: __Key_sheetStore.Value {
        get { self[__Key_sheetStore.self] }
        set { self[__Key_sheetStore.self] = newValue }
    }
    struct __Key_sheetStore: EnvironmentKey { static let defaultValue = UncheckedSendable<Any?>(wrappedValue: nil) }

    /// The backend's representation of the sheet that the current view is
    /// in, if any.
    ///
    /// This is a very internal detail that should never get exposed to users.
    @_spi(Backends) public var sheet: Any? {
        get {
            sheetStore.wrappedValue
        }
        set {
            sheetStore.wrappedValue = newValue
        }
    }

    /// The current calendar that views should use when handling dates.
    public var calendar: Calendar {
        get { self[__Key_calendar.self] }
        set { self[__Key_calendar.self] = newValue }
    }
    struct __Key_calendar: EnvironmentKey { static var defaultValue: Calendar { .current } }

    /// The current time zone that views should use when handling dates.
    public var timeZone: TimeZone {
        get { self[__Key_timeZone.self] }
        set { self[__Key_timeZone.self] = newValue }
    }
    struct __Key_timeZone: EnvironmentKey { static var defaultValue: TimeZone { .current } }

    /// The current locale.
    public var locale: Locale {
        get { self[__Key_locale.self] }
        set { self[__Key_locale.self] = newValue }
    }
    struct __Key_locale: EnvironmentKey { static var defaultValue: Locale { .current } }

    /// The display style used by ``Picker``.
    public var pickerStyle: any PickerStyle {
        get { self[__Key_pickerStyle.self] }
        set { self[__Key_pickerStyle.self] = newValue }
    }
    struct __Key_pickerStyle: EnvironmentKey { static var defaultValue: any PickerStyle { .automatic } }

    /// The display style used by ``DatePicker``.
    public var datePickerStyle: DatePickerStyle {
        get { self[__Key_datePickerStyle.self] }
        set { self[__Key_datePickerStyle.self] = newValue }
    }
    struct __Key_datePickerStyle: EnvironmentKey { static var defaultValue: DatePickerStyle { .automatic } }

    /// Whether user interaction is enabled.
    ///
    /// Set by ``View/disabled(_:)``.
    public var isEnabled: Bool {
        get { self[__Key_isEnabled.self] }
        set { self[__Key_isEnabled.self] = newValue }
    }
    struct __Key_isEnabled: EnvironmentKey { static var defaultValue: Bool { true } }

    /// The number of lines text can occupy and whether to reserve that space.
    public var lineLimitSettings: LineLimit? {
        get { self[__Key_lineLimitSettings.self] }
        set { self[__Key_lineLimitSettings.self] = newValue }
    }
    struct __Key_lineLimitSettings: EnvironmentKey { static var defaultValue: LineLimit? { nil } }

    /// The maximum number of lines that text can occupy in a view.
    public var lineLimit: Int? {
        lineLimitSettings?.limit
    }

    /// Whether the current device has a circular screen. Primarily Android smart watches.
    public var isCircularScreen: Bool {
        get { self[__Key_isCircularScreen.self] }
        set { self[__Key_isCircularScreen.self] = newValue }
    }
    struct __Key_isCircularScreen: EnvironmentKey { static var defaultValue: Bool { false } }

    /// The display style used by ``Button``.
    public var buttonStyle: ButtonStyle? {
        get { self[__Key_buttonStyle.self] }
        set { self[__Key_buttonStyle.self] = newValue }
    }
    struct __Key_buttonStyle: EnvironmentKey { static var defaultValue: ButtonStyle? { nil } }

    /// The default button style as declared by the backend.
    @MainActor
    public var defaultButtonStyle: ButtonStyle {
        backend.defaultButtonStyle()
    }

    /// The resolved ``ButtonStyle``. Either ``buttonStyle``, or ``defaultButtonStyle`` if nil.
    @MainActor
    public var resolvedButtonStyle: ButtonStyle {
        buttonStyle ?? defaultButtonStyle
    }

    /// The amount of padding that the current backend applies to the labels of buttons with the current ``ButtonStyle``.
    @MainActor
    public var buttonPadding: SIMD2<Int> {
        backend.buttonPadding(in: self)
    }

    /// The device class of the current device.
    @MainActor
    public var deviceClass: DeviceClass { backend.deviceClass }

    /// All observers set by ``View/focused(_:)`` in the environment.
    @_spi(Backends) public var widgetFocusObservers: [WidgetFocusObserver] {
        get { self[__Key_widgetFocusObservers.self] }
        set { self[__Key_widgetFocusObservers.self] = newValue }
    }
    struct __Key_widgetFocusObservers: EnvironmentKey { static var defaultValue: [WidgetFocusObserver] { [] } }

    /// A value used to make widgets programmatically gain or lose focus.
    @_spi(Backends) public var focusOverride: Focus? {
        get { self[__Key_focusOverride.self] }
        set { self[__Key_focusOverride.self] = newValue }
    }
    struct __Key_focusOverride: EnvironmentKey { static var defaultValue: Focus? { nil } }

    /// Whether to highlight a focused widget.
    public var focusEffectDisabled: Bool {
        get { self[__Key_focusEffectDisabled.self] }
        set { self[__Key_focusEffectDisabled.self] = newValue }
    }
    struct __Key_focusEffectDisabled: EnvironmentKey { static var defaultValue: Bool { false } }
}

extension EnvironmentValues {
    func applyingTextTransforms(to string: String) -> String {
        var string = string

        switch textCase {
            case .lowercase: string = string.lowercased(with: locale)
            case .uppercase: string = string.uppercased(with: locale)
            case nil: break
        }

        return string
    }
}

/// A key that can be used to extend the environment with new properties.
public protocol EnvironmentKey<Value> {
    /// The type of value the key can hold.
    associatedtype Value
    /// The default value for the key.
    static var defaultValue: Value { get }
}
