#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

#if os(Windows)
extension View {
    func factText(_ key: String) -> some View { self }
    func factFrame(_ key: String) -> some View { self }
}
#else
final class FactLedger: @unchecked Sendable {
    static let shared = FactLedger()
    func record(_ key: String, _ field: String, _ v: Double) {
        print("MAC_FACT row=\(key) \(field)=\((v * 100).rounded() / 100)")
        fflush(nil)
    }
}
extension View {
    func factText(_ key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            self
                .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                    Color.clear.frame(height: 0).background(GeometryReader { g in
                        let _ = FactLedger.shared.record(key, "baselineOverlayTop", Double(g.frame(in: .global).minY))
                        Color.clear
                    })
                }
                .overlay(alignment: Alignment(horizontal: .leading, vertical: .lastTextBaseline)) {
                    Color.clear.frame(height: 0).background(GeometryReader { g in
                        let _ = FactLedger.shared.record(key, "lastBaselineOverlayTop", Double(g.frame(in: .global).minY))
                        Color.clear
                    })
                }
                .alignmentGuide(.firstTextBaseline) { d in
                    let b = d[.firstTextBaseline]
                    FactLedger.shared.record(key, "baseline", Double(b))
                    return b
                }
                .alignmentGuide(.lastTextBaseline) { d in
                    let b = d[.lastTextBaseline]
                    FactLedger.shared.record(key, "lastBaseline", Double(b))
                    return b
                }
                .background(GeometryReader { g in
                    let _ = FactLedger.shared.record(key, "textTop", Double(g.frame(in: .global).minY))
                    let _ = FactLedger.shared.record(key, "textH", Double(g.size.height))
                    Color.clear
                })
            Text("|").font(.system(size: 8)).opacity(0).frame(width: 0)
        }
    }
    func factFrame(_ key: String) -> some View {
        self.background(GeometryReader { g in
            let _ = FactLedger.shared.record(key, "frameTop", Double(g.frame(in: .global).minY))
            let _ = FactLedger.shared.record(key, "frameH", Double(g.size.height))
            Color.clear
        })
    }
}
#endif

struct Witness_sf_frame_centring_facts_b: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Headroom of memory pressure and swap activity across every running process").font(Font.system(size: 12, weight: .regular)).lineLimit(2).factText("ll2-w110h60").frame(width: 110, height: 60, alignment: .leading).factFrame("ll2-w110h60")
            Text("Headroom of memory pressure and swap activity across every running process").font(Font.system(size: 12, weight: .regular)).lineLimit(3).factText("ll3-w110h60").frame(width: 110, height: 60, alignment: .leading).factFrame("ll3-w110h60")
            Text("Headroom").font(Font.system(size: 12, weight: .regular)).factText("f12r-w110h60").frame(width: 110, height: 60, alignment: .leading).factFrame("f12r-w110h60")
            Text("Hxg Overview").font(Font.system(size: 12, weight: .regular)).factText("f12r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f12r-h40")
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
