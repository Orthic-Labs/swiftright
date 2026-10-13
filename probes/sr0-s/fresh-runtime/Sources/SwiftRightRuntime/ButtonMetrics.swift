import Foundation

/// How a Button is drawn on macOS, which decides its intrinsic size. Measured from SwiftUI on macOS (AppKit-hosted `NSHostingView.fittingSize`) for labels of
/// text and of fixed-size views: the bordered push button is its label plus 12 pt on each side and 4 pt above and below (a 16 pt line of body text gives
/// the 24 pt standard button height). The artwork itself is host-owned (SwiftRightHost `ButtonArtwork`).
public enum ButtonMetrics {
    public static let padding = LayoutSize(width: 12, height: 4)

    /// The padding of a Button look: the push-button looks pad their label, `.borderless` and `.plain` are the label alone (measured: `Button("Run")` is
    /// 48 x 24 pt bordered or prominent and 24 x 16 pt borderless or plain; a 30 x 10 pt view label gives 54 x 18 and 30 x 10).
    public static func padding(for look: ButtonLook) -> LayoutSize { look.hasBody ? padding : LayoutSize(width: 0, height: 0) }
}
