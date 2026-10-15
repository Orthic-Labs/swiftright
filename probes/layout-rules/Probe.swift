// Mac measurement probe for the SwiftUI Text / stack distribution rules (decisions L1.. in docs/sr1-decisions.md).
// Offscreen: views live in an NSHostingView that has no window and is never shown; nothing is drawn.
// A Layout wrapper (Rec) around each child records the size the stack finally assigned it; the Text rules are read with a Layout that asks its child for sizeThatFits.
// Output: one JSON object per line on stdout (kind: text | stack | vstack), consumed by analyse.py.
import SwiftUI
import AppKit

nonisolated(unsafe) var recorded: [String: CGSize] = [:]

struct Rec: Layout {
    let id: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        recorded[id] = bounds.size
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

struct Ask: Layout {
    let p: ProposedViewSize
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(p)
        recorded["ask"] = s
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

func j(_ d: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
func num(_ v: CGFloat?) -> Any { guard let v else { return "nil" }; return v.isInfinite ? "inf" : Double(v) }

@MainActor func layout<V: View>(_ v: V, size: CGSize) {
    let host = NSHostingView(rootView: v)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    _ = host.fittingSize
}

let A = "Unused 90+ days", B = "Demo Install", S = "Hi", L = "Settings and preferences for the application"
let texts: [(String, String)] = [("A", A), ("B", B), ("S", S), ("L", L)]

@MainActor func textRules() {
    let widths: [CGFloat?] = [0, 1, 5, 10, 14, 20, 30, 45, 60, 80, 120, 200, nil, .infinity]
    for (tn, t) in texts {
        for ll in [0, 1, 2] {            // 0 = nil
            for trunc in ["tail", "middle", "head"] where ll == 1 || trunc == "tail" {
                for w in widths {
                    for hProp in [CGFloat?.none, 0] {
                        recorded["ask"] = nil
                        let mode: Text.TruncationMode = trunc == "tail" ? .tail : trunc == "middle" ? .middle : .head
                        let base = Text(t).lineLimit(ll == 0 ? nil : ll).truncationMode(mode)
                        layout(Ask(p: ProposedViewSize(width: w, height: hProp)) { base }, size: CGSize(width: 500, height: 500))
                        let s = recorded["ask"] ?? .zero
                        j(["kind": "text", "text": tn, "lineLimit": ll, "trunc": trunc, "w": num(w), "h": num(hProp), "outW": Double(s.width), "outH": Double(s.height)])
                    }
                }
            }
        }
    }
    // fixedSize: a fixedSize Text ignores the proposal on that axis
    for (tn, t) in texts {
        for w in [CGFloat?.some(0), 10, 60, nil] {
            recorded["ask"] = nil
            layout(Ask(p: ProposedViewSize(width: w, height: nil)) { Text(t).fixedSize() }, size: CGSize(width: 500, height: 500))
            let s = recorded["ask"] ?? .zero
            j(["kind": "text", "text": tn, "lineLimit": -1, "trunc": "fixedSize", "w": num(w), "h": "nil", "outW": Double(s.width), "outH": Double(s.height)])
            recorded["ask"] = nil
            layout(Ask(p: ProposedViewSize(width: w, height: nil)) { Text(t).fixedSize(horizontal: false, vertical: true) }, size: CGSize(width: 500, height: 500))
            let s2 = recorded["ask"] ?? .zero
            j(["kind": "text", "text": tn, "lineLimit": -1, "trunc": "fixedSizeV", "w": num(w), "h": "nil", "outW": Double(s2.width), "outH": Double(s2.height)])
        }
    }
}

struct Kid {
    var label: String
    var make: () -> AnyView
    var prio: Double = 0
    var spacer: Bool = false
    var spacerMin: CGFloat? = nil
}
func T(_ label: String, _ t: String, ll: Int = 0, prio: Double = 0, fixed: Bool = false, trunc: Text.TruncationMode = .tail) -> Kid {
    Kid(label: label, make: {
        let base = Text(t).lineLimit(ll == 0 ? nil : ll).truncationMode(trunc)
        return fixed ? AnyView(base.fixedSize(horizontal: true, vertical: false)) : AnyView(base)
    }, prio: prio)
}
func SP(_ label: String = "sp", min: CGFloat? = nil, prio: Double = 0) -> Kid { Kid(label: label, make: { AnyView(EmptyView()) }, prio: prio, spacer: true, spacerMin: min) }
func RECT(_ label: String, prio: Double = 0) -> Kid { Kid(label: label, make: { AnyView(Color.gray) }, prio: prio) }
func FLEXR(_ label: String, prio: Double = 0, min: CGFloat = 20, max: CGFloat = 150) -> Kid { Kid(label: label, make: { AnyView(Color.gray.frame(minWidth: min, idealWidth: 100, maxWidth: max, minHeight: 20, idealHeight: 20, maxHeight: 20)) }, prio: prio) }
func FIX(_ label: String, w: CGFloat, prio: Double = 0) -> Kid { Kid(label: label, make: { AnyView(Color.gray.frame(width: w, height: 10)) }, prio: prio) }

struct Stack: View {
    let kids: [Kid]; let spacing: CGFloat; let vertical: Bool
    var body: some View {
        let content = ForEach(0..<kids.count, id: \.self) { i in
            let k = kids[i]
            if k.spacer {
                // a bare Spacer: wrapping it in AnyView hides it from the stack (measured: the stack then treats it as an ordinary flexible child)
                if k.prio == 0 { Spacer(minLength: k.spacerMin) } else { Spacer(minLength: k.spacerMin).layoutPriority(k.prio) }
            }
            else { Rec(id: "s/\(k.label)") { k.make() }.layoutPriority(k.prio) }
        }
        if vertical { VStack(spacing: spacing) { content } } else { HStack(spacing: spacing) { content } }
    }
}

@MainActor func runStack(_ name: String, _ kids: [Kid], widths: [CGFloat], spacing: CGFloat = 8, vertical: Bool = false, cross: CGFloat = 200) {
    for w in widths {
        recorded = [:]
        let frame = vertical ? CGSize(width: cross, height: w) : CGSize(width: w, height: cross)
        layout(Stack(kids: kids, spacing: spacing, vertical: vertical).frame(width: frame.width, height: frame.height, alignment: .topLeading), size: frame)
        var out: [String: Any] = ["kind": vertical ? "vstack" : "stack", "name": name, "w": Double(w), "spacing": Double(spacing)]
        var sizes: [Double] = []
        for k in kids where !k.spacer {
            let s = recorded["s/\(k.label)"] ?? CGSize(width: -1, height: -1)
            sizes.append(Double(vertical ? s.height : s.width))
        }
        out["labels"] = kids.filter { !$0.spacer }.map { $0.label }
        out["sizes"] = sizes
        out["prios"] = kids.filter { !$0.spacer }.map { $0.prio }
        j(out)
    }
}

@MainActor func stackRules() {
    let ws: [CGFloat] = [20, 40, 60, 80, 100, 120, 140, 160, 200, 300]
    for ll in [0, 1, 2] {
        let tag = ll == 0 ? "nolimit" : "ll\(ll)"
        runStack("A+S \(tag)", [T("A", A, ll: ll), T("S", S, ll: ll)], widths: ws)
        runStack("A+B \(tag)", [T("A", A, ll: ll), T("B", B, ll: ll)], widths: ws)
        runStack("L+S \(tag)", [T("L", L, ll: ll), T("S", S, ll: ll)], widths: [40, 80, 120, 160, 200, 260, 400])
        runStack("S+L \(tag)", [T("S", S, ll: ll), T("L", L, ll: ll)], widths: [40, 80, 120, 160, 200, 260, 400])
        runStack("L+A+B \(tag)", [T("L", L, ll: ll), T("A", A, ll: ll), T("B", B, ll: ll)], widths: [60, 100, 160, 220, 300, 400])
        runStack("L+A+B+S \(tag)", [T("L", L, ll: ll), T("A", A, ll: ll), T("B", B, ll: ll), T("S", S, ll: ll)], widths: [60, 100, 160, 220, 300, 400])
    }
    runStack("A+S middle", [T("A", A, ll: 1, trunc: .middle), T("S", S, ll: 1, trunc: .middle)], widths: ws)
    // priority across groups
    runStack("A(p1)+B", [T("A", A, ll: 1, prio: 1), T("B", B, ll: 1)], widths: ws)
    runStack("A+B(p1)", [T("A", A, ll: 1), T("B", B, ll: 1, prio: 1)], widths: ws)
    runStack("A(p1)+B nolimit", [T("A", A, prio: 1), T("B", B)], widths: ws)
    runStack("A+B(p1) nolimit", [T("A", A), T("B", B, prio: 1)], widths: ws)
    runStack("L(p1)+S+A", [T("L", L, ll: 1, prio: 1), T("S", S, ll: 1), T("A", A, ll: 1)], widths: [40, 80, 120, 160, 220, 300, 400])
    runStack("three groups L p2, A p1, B p0", [T("L", L, ll: 1, prio: 2), T("A", A, ll: 1, prio: 1), T("B", B, ll: 1)], widths: [40, 80, 120, 160, 220, 300, 400])
    runStack("three groups L p0, A p1, B p2", [T("L", L, ll: 1), T("A", A, ll: 1, prio: 1), T("B", B, ll: 1, prio: 2)], widths: [40, 80, 120, 160, 220, 300, 400])
    runStack("group p1 {L,S} + A p0", [T("L", L, ll: 1, prio: 1), T("S", S, ll: 1, prio: 1), T("A", A, ll: 1)], widths: [40, 80, 120, 160, 220, 300, 400])
    runStack("group p1 {A,B} + L p0 + S p0", [T("A", A, ll: 1, prio: 1), T("B", B, ll: 1, prio: 1), T("L", L, ll: 1), T("S", S, ll: 1)], widths: [40, 80, 120, 160, 220, 300, 400])
    runStack("neg prio L(-1)+A", [T("L", L, ll: 1, prio: -1), T("A", A, ll: 1)], widths: ws)
    runStack("fractional prio A(0.5)+B(0.25)", [T("A", A, ll: 1, prio: 0.5), T("B", B, ll: 1, prio: 0.25)], widths: ws)
    // spacers
    runStack("A+Spacer+B", [T("A", A, ll: 1), SP(), T("B", B, ll: 1)], widths: ws)
    runStack("A+Spacer+B nolimit", [T("A", A), SP(), T("B", B)], widths: ws)
    runStack("A+Spacer+B(p1)", [T("A", A, ll: 1), SP(), T("B", B, ll: 1, prio: 1)], widths: ws)
    runStack("Spacer+A", [SP(), T("A", A, ll: 1)], widths: ws)
    runStack("A+Spacer(min 30)+B", [T("A", A, ll: 1), SP(min: 30), T("B", B, ll: 1)], widths: ws)
    runStack("L+Spacer+S", [T("L", L, ll: 1), SP(), T("S", S, ll: 1)], widths: [40, 80, 120, 200, 300, 400])
    runStack("A+Spacer(p1)+B", [T("A", A, ll: 1), SP(prio: 1), T("B", B, ll: 1)], widths: ws)
    runStack("A+Rect+B", [T("A", A, ll: 1), RECT("R"), T("B", B, ll: 1)], widths: ws)
    runStack("A+Fix40+B", [T("A", A, ll: 1), FIX("F", w: 40), T("B", B, ll: 1)], widths: ws)
    // fixedSize
    runStack("A fixed + B", [T("A", A, ll: 1, fixed: true), T("B", B, ll: 1)], widths: ws)
    runStack("A fixed + L", [T("A", A, fixed: true), T("L", L)], widths: [40, 80, 120, 160, 220, 300, 400])
    runStack("A fixed(p1) + B", [T("A", A, ll: 1, prio: 1, fixed: true), T("B", B, ll: 1)], widths: ws)
    runStack("A + B fixed(p1) + S", [T("A", A, ll: 1), T("B", B, ll: 1, prio: 1, fixed: true), T("S", S, ll: 1)], widths: ws)
    // a lower group with a non-zero minimum (fixed frame / fixedSize text): is it kept in reserve for the higher group?
    runStack("A(p1)+Fix40(p0)", [T("A", A, ll: 1, prio: 1), FIX("F", w: 40)], widths: [40, 60, 80, 100, 140, 200, 300])
    runStack("A(p1)+B(p0)+Fix40(p0)", [T("A", A, ll: 1, prio: 1), T("B", B, ll: 1), FIX("F", w: 40)], widths: [40, 60, 80, 100, 140, 200, 300])
    runStack("A(p1)+B fixed(p0)", [T("A", A, ll: 1, prio: 1), T("B", B, ll: 1, fixed: true)], widths: [40, 60, 80, 100, 140, 200, 300])
    runStack("A+Fix40(p1)", [T("A", A, ll: 1), FIX("F", w: 40, prio: 1)], widths: [40, 60, 80, 100, 140, 200, 300])
    runStack("A(p1)+Spacer+Fix40", [T("A", A, ll: 1, prio: 1), SP(), FIX("F", w: 40)], widths: [40, 60, 80, 100, 140, 200, 300])
    runStack("A(p1)+Spacer(min30)+B", [T("A", A, ll: 1, prio: 1), SP(min: 30), T("B", B, ll: 1)], widths: [40, 60, 80, 100, 140, 200, 300])
    runStack("spacing0 A+B", [T("A", A, ll: 1), T("B", B, ll: 1)], widths: [40, 80, 120, 160], spacing: 0)
    // flexible rectangles (the block 27 witness: min 20, ideal 100, max 150) next to spacers: the old model, measured with the same wrapper
    runStack("R+Spacer+B (rects) s0", [FLEXR("R"), SP(), FLEXR("B")], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("R+Spacer(min0)+B (rects) s0", [FLEXR("R"), SP(min: 0), FLEXR("B")], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("R+Spacer+B(p1) (rects) s0", [FLEXR("R"), SP(), FLEXR("B", prio: 1)], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("R+Spacer(30)+B(p1) (rects) s0", [FLEXR("R"), SP(min: 30), FLEXR("B", prio: 1)], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("R+B (rects) s0", [FLEXR("R"), FLEXR("B")], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("R+Spacer+B (rects min0) s0", [FLEXR("R", min: 0), SP(), FLEXR("B", min: 0)], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("A+Spacer+B nolimit s0", [T("A", A), SP(), T("B", B)], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("A+Spacer+B ll1 s0", [T("A", A, ll: 1), SP(), T("B", B, ll: 1)], widths: [100, 150, 200, 240, 300, 400], spacing: 0)
    runStack("A+Spacer+B ll1 s0 unwrapped", [T("A", A, ll: 1), SP(), T("B", B, ll: 1)], widths: [180, 190, 200, 210], spacing: 0)
    // vertical stacks (main axis = height) with wrapping Text
    runStack("V L+L", [T("L", L), T("L2", L)], widths: [10, 20, 30, 40, 60, 80, 120], vertical: true, cross: 100)
    runStack("V L+S", [T("L", L), T("S", S)], widths: [10, 20, 30, 40, 60, 80, 120], vertical: true, cross: 100)
    runStack("V L(p1)+L2", [T("L", L, prio: 1), T("L2", L)], widths: [10, 20, 30, 40, 60, 80, 120], vertical: true, cross: 100)
    runStack("V L ll2+L2 ll2", [T("L", L, ll: 2), T("L2", L, ll: 2)], widths: [10, 20, 30, 40, 60, 80, 120], vertical: true, cross: 100)
}

/// Natural widths of the probe texts in a bundled font (case design: `Probe tinos <font file>`).
@MainActor func tinosWidths(_ file: String) {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: file) as CFURL, .process, nil)
    for (tn, t) in texts {
        for ll in [1] {
            recorded["ask"] = nil
            layout(Ask(p: ProposedViewSize(width: nil, height: nil)) { Text(t).font(.custom("Tinos-Regular", size: 13)).lineLimit(ll) }, size: CGSize(width: 500, height: 500))
            let s = recorded["ask"] ?? .zero
            j(["kind": "tinos", "text": tn, "outW": Double(s.width), "outH": Double(s.height)])
        }
    }
}

@main struct Main {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let sel = CommandLine.arguments.dropFirst().first ?? "all"
        if sel == "tinos" { tinosWidths(CommandLine.arguments[2]); return }
        if sel == "all" || sel == "text" { textRules() }
        if sel == "all" || sel == "stack" { stackRules() }
    }
}
