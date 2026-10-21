import SwiftUI
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum NetworkImageState {
    case empty
    case success(image: Image, idealSize: CGSize)
    case failure
}

public struct NetworkImage<Content: View>: View {
    var url: URL?
    var content: (NetworkImageState) -> Content
    public init(url: URL?, @ViewBuilder content: @escaping (NetworkImageState) -> Content) {
        self.url = url
        self.content = content
    }
    public var body: some View { content(.empty) }
}

public struct DefaultNetworkImageLoader: Sendable {
    public static let shared = DefaultNetworkImageLoader()
    public func image(from url: URL) async throws -> RGBAImage { throw URLError(.unsupportedURL) }  // SwiftRight: decoded pixels, not CGImage
}
