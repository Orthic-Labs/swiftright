import SwiftRightRuntime
struct FactoryChannelWitness: View {
    @State private var changed = false
    func changeContent() { changed.toggle() }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(changed ? Color.blue : Color.red).frame(width: 48, height: 48)
                Rectangle().fill(changed ? Color.red : Color.blue).frame(width: 48, height: 48)
            }
            HStack(spacing: 0) {
                Rectangle().fill(changed ? Color.red : Color.blue).frame(width: 48, height: 48)
                Rectangle().fill(changed ? Color.blue : Color.red).frame(width: 48, height: 48)
            }
            Text(changed ? "CONTROL phase B" : "CONTROL phase A").font(.system(size: 18, weight: .bold)).frame(width: 220, height: 30)
        }.padding(8)
    }
}
