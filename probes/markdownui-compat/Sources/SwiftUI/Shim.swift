// Probe-only: makes `import SwiftUI` resolve to the SwiftRight runtime (real SwiftUI re-exports Foundation, so does this).
@_exported import SwiftRightRuntime
@_exported import Foundation
#if canImport(CoreGraphics)
@_exported import CoreGraphics  // real SwiftUI re-exports it (CGRectUnion etc.); on Windows the runtime provides CGRectUnion
#endif
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking  // URLSession lives here on Windows and Linux
#endif
