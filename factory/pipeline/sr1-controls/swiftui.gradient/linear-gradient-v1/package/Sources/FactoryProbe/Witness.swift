#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #60, case linear-gradient-v1: LinearGradient as a shape fill, smooth (no bands). A Rectangle row over a RoundedRectangle row; the four columns are a 2-stop and a
// 3-stop gradient, each at 0 degrees (leading to trailing) and at 45 degrees (topLeading to bottomTrailing on a square cell, so the line runs exactly corner to corner).
// Colours are explicit sRGB components so no semantic colour mapping enters the comparison.
struct Witness_p60_linear_gradient_v1: View {
    static let twoStop = Gradient(colors: [Color(red: 0.0, green: 0.4, blue: 1.0), Color(red: 1.0, green: 0.6, blue: 0.0)])
    static let threeStop = Gradient(colors: [Color(red: 0.9, green: 0.1, blue: 0.2), Color(red: 1.0, green: 0.85, blue: 0.1), Color(red: 0.1, green: 0.7, blue: 0.3)])

    func rectangle(_ gradient: Gradient, _ start: UnitPoint, _ end: UnitPoint) -> some View {
        Rectangle().fill(LinearGradient(gradient: gradient, startPoint: start, endPoint: end)).frame(width: 60, height: 60)
    }

    func rounded(_ gradient: Gradient, _ start: UnitPoint, _ end: UnitPoint) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .circular).fill(LinearGradient(gradient: gradient, startPoint: start, endPoint: end)).frame(width: 60, height: 60)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                rectangle(Self.twoStop, .leading, .trailing)
                rectangle(Self.twoStop, .topLeading, .bottomTrailing)
                rectangle(Self.threeStop, .leading, .trailing)
                rectangle(Self.threeStop, .topLeading, .bottomTrailing)
            }
            HStack(spacing: 10) {
                rounded(Self.twoStop, .leading, .trailing)
                rounded(Self.twoStop, .topLeading, .bottomTrailing)
                rounded(Self.threeStop, .leading, .trailing)
                rounded(Self.threeStop, .topLeading, .bottomTrailing)
            }
        }
        .frame(width: 300, height: 160)
    }
}
