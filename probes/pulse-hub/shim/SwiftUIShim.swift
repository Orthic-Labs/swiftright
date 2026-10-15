// Probe-only: Pulse's sources say `import SwiftUI`; on Windows there is no such module, so this target
// is named SwiftUI and re-exports the SwiftRight runtime (as the MarkdownUI probe did).
@_exported import SwiftRightRuntime
@_exported import Foundation
