import SwiftRightRuntime

@main
struct LayoutProbe {
    static func main() {
        print("ResolvedNode size=\(MemoryLayout<ResolvedNode>.size) stride=\(MemoryLayout<ResolvedNode>.stride) alignment=\(MemoryLayout<ResolvedNode>.alignment)")
        print("ResolvedAccessibility size=\(MemoryLayout<ResolvedAccessibility>.size) stride=\(MemoryLayout<ResolvedAccessibility>.stride)")
        print("ResolvedStyle size=\(MemoryLayout<ResolvedStyle>.size) stride=\(MemoryLayout<ResolvedStyle>.stride)")
        print("ResolvedColor size=\(MemoryLayout<ResolvedColor>.size) stride=\(MemoryLayout<ResolvedColor>.stride)")
        print("Font size=\(MemoryLayout<Font>.size) stride=\(MemoryLayout<Font>.stride)")
    }
}
