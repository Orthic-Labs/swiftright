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
    private var values: [String: [String: Double]] = [:]
    private var done: Set<String> = []
    func record(_ key: String, _ field: String, _ v: Double) {
        values[key, default: [:]][field] = v
        guard !done.contains(key), let d = values[key], d.count == 5 else { return }
        done.insert(key)
        print("MAC_FACT row=\(key) frameTop=\(r(d["frameTop"]!)) frameH=\(r(d["frameH"]!)) textTop=\(r(d["textTop"]!)) textH=\(r(d["textH"]!)) baseline=\(r(d["baseline"]!))")
    }
    private func r(_ v: Double) -> String { "\((v * 100).rounded() / 100)" }
}
extension View {
    func factText(_ key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            self
                .alignmentGuide(.firstTextBaseline) { d in
                    let b = d[.firstTextBaseline]
                    FactLedger.shared.record(key, "baseline", Double(b))
                    return b
                }
                .background(GeometryReader { g in
                    Color.clear.onAppear {
                        FactLedger.shared.record(key, "textTop", Double(g.frame(in: .global).minY))
                        FactLedger.shared.record(key, "textH", Double(g.size.height))
                    }
                })
        }
    }
    func factFrame(_ key: String) -> some View {
        self.background(GeometryReader { g in
            Color.clear.onAppear {
                FactLedger.shared.record(key, "frameTop", Double(g.frame(in: .global).minY))
                FactLedger.shared.record(key, "frameH", Double(g.size.height))
            }
        })
    }
}
#endif

struct Witness_sf_frame_centring_facts: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(Font.system(size: 11.5, weight: .regular)).factText("f11.5r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f11.5r-h40")
            Text("Hxg Overview").font(Font.system(size: 12, weight: .regular)).factText("f12r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f12r-h40")
            Text("Hxg Overview").font(Font.system(size: 13, weight: .semibold)).factText("f13sb-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f13sb-h40")
            Text("Hxg Overview").font(Font.system(size: 18, weight: .regular)).factText("f18r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f18r-h40")
            Text("Hxg Overview").font(Font.system(size: 24, weight: .regular)).factText("f24r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f24r-h40")
            Text("Hxg Overview").font(Font.system(size: 28, weight: .regular)).factText("f28r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f28r-h40")
            Text("Hxg Overview").font(Font.system(size: 28, weight: .regular)).factText("f28r-h60").frame(width: 240, height: 60, alignment: .center).factFrame("f28r-h60")
            Text("Hxg Overview").font(Font.system(size: 32, weight: .regular)).factText("f32r-h40").frame(width: 240, height: 40, alignment: .center).factFrame("f32r-h40")
            Text("Hxg Overview").font(Font.system(size: 32, weight: .regular)).factText("f32r-h60").frame(width: 240, height: 60, alignment: .center).factFrame("f32r-h60")
            Text("Overview of memory pressure and swap activity across every running process").font(Font.system(size: 12, weight: .regular)).lineLimit(2).factText("ll2-w110h60").frame(width: 110, height: 60, alignment: .leading).factFrame("ll2-w110h60")
            Text("Overview of memory pressure and swap activity across every running process").font(Font.system(size: 12, weight: .regular)).lineLimit(3).factText("ll3-w110h60").frame(width: 110, height: 60, alignment: .leading).factFrame("ll3-w110h60")
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
