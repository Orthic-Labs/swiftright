#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case completion: withAnimation(_:completionCriteria:_:completion:) with the default spring. `.logicallyComplete` fires at the spring's
// perceptual duration (0.5 s), `.removed` when it settles (0.536 s at scale 1 for 100 pt, 0.63 s at the capture scale 2.5). Each completion turns a flag from red to green (a state change without animation).
struct Witness_anim_completion: View {
    @State private var wide = false
    @State private var wide2 = false
    @State private var logical = false
    @State private var removed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.blue.frame(width: wide ? 200 : 100, height: 20)
            Color.blue.frame(width: wide2 ? 200 : 100, height: 20)
            HStack(spacing: 8) {
                (logical ? Color.green : Color.red).frame(width: 40, height: 20)
                (removed ? Color.green : Color.red).frame(width: 40, height: 20)
            }
        }
        .frame(width: 300, height: 100, alignment: .topLeading)
        .onAppear {
            withAnimation(FactoryAnim.wrap(.default), completionCriteria: .logicallyComplete) { wide = true } completion: { logical = true }
            FactoryClock.at(0) {
                withAnimation(FactoryAnim.wrap(.default), completionCriteria: .removed) { wide2 = true } completion: { removed = true }
            }
        }
    }
}
