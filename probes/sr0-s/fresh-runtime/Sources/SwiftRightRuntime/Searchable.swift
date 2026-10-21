import Foundation

// Issue #60 (SR1 backlog), first pass: `.searchable(text:placement:prompt:)`.
//
// ADAPTATION: on macOS `searchable` puts a search field in the window toolbar (or the sidebar's top) and the app filters its own data by the bound text. The runtime
// has no window toolbar, so the modifier wraps the view in a column: a search-field ROW on top (a magnifier, a plain text field with the prompt as its placeholder,
// and a clear button while the text is non-empty), the view below. The text is the caller's binding (carried, not owned); filtering stays the caller's job, as in
// SwiftUI. `placement` is carried and has no effect (the row is always on top of the modified view). Not modelled: suggestions, tokens, scopes, `isSearching`, the
// Escape key and the Cmd-F focus shortcut.
// Metrics are guesses: the row is 22 pt tall inside 8 pt padding, the field a 6 pt rounded rectangle at 12% grey.

/// Apple: https://developer.apple.com/documentation/swiftui/searchfieldplacement
public struct SearchFieldPlacement: Hashable, Sendable {
    let name: String
    private init(_ name: String) { self.name = name }

    public static let automatic = SearchFieldPlacement("automatic")
    public static let toolbar = SearchFieldPlacement("toolbar")
    public static let sidebar = SearchFieldPlacement("sidebar")
    public static let toolbarPrincipal = SearchFieldPlacement("toolbarPrincipal")
}

enum SearchFieldMetrics {
    static let height: CGFloat = 22
    static let outerPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 6
}

/// The search-field row.
struct SearchFieldRow: View {
    let text: Binding<String>
    let prompt: String

    @MainActor var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
            if !text.wrappedValue.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.secondary)
                    .onTapGesture { text.wrappedValue = "" }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: SearchFieldMetrics.height)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: SearchFieldMetrics.cornerRadius))
        .padding(SearchFieldMetrics.outerPadding)
    }
}

struct SearchableHost<Base: View>: View {
    let base: Base
    let text: Binding<String>
    let placement: SearchFieldPlacement
    let prompt: String

    @MainActor var body: some View {
        VStack(spacing: 0) {
            SearchFieldRow(text: text, prompt: prompt)
            base
        }
    }
}

extension View {
    /// Adds a search field row above this view, bound to `text` (see the file header for the adaptation).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search"
    ) -> some View {
        SearchableHost(base: self, text: text, placement: placement, prompt: prompt)
    }
}
