import SwiftUI

struct Witness_image_baseline: View {
    var body: some View {
        Image(systemName: "star.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
            .foregroundStyle(.yellow)
            .environment(\.colorScheme, .light)
    }
}
