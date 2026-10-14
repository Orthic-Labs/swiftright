// AppKit facts for the TextField bezel: selection colours and NSTextFieldCell insets. No window is shown.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func rgba(_ c: NSColor, _ name: String) {
    for (an, ap) in [("aqua", NSAppearance(named: .aqua)!), ("darkAqua", NSAppearance(named: .darkAqua)!)] {
        ap.performAsCurrentDrawingAppearance {
            let s = c.usingColorSpace(.sRGB)!
            print(name, an, String(format: "r=%.4f g=%.4f b=%.4f a=%.4f", s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent),
                  "over white:", [s.redComponent, s.greenComponent, s.blueComponent].map { Int(round(($0 * s.alphaComponent + (1 - s.alphaComponent)) * 255)) })
        }
    }
}
rgba(.selectedTextBackgroundColor, "selectedTextBackground (emphasized)")
rgba(.unemphasizedSelectedTextBackgroundColor, "unemphasizedSelectedTextBackground")
rgba(.controlAccentColor, "controlAccent")

for style in [NSTextField.BezelStyle.roundedBezel, .squareBezel] {
    for cs in [NSControl.ControlSize.regular, .small, .mini] {
        let cell = NSTextFieldCell(textCell: "Hello")
        cell.isBezeled = true; cell.bezelStyle = style; cell.controlSize = cs
        cell.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: cs))
        let b = NSRect(x: 0, y: 0, width: 120, height: 24)
        print("bezel", style.rawValue, "cs", cs.rawValue, "drawingRect", cell.drawingRect(forBounds: b), "titleRect", cell.titleRect(forBounds: b), "cellSize", cell.cellSize)
    }
}
let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
tf.stringValue = "Hello"; tf.isBezeled = true; tf.bezelStyle = .roundedBezel
let tc = tf.cell as! NSTextFieldCell
print("NSTextField drawingRect", tc.drawingRect(forBounds: tf.bounds), "titleRect", tc.titleRect(forBounds: tf.bounds), "bezelStyle", tc.bezelStyle.rawValue)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60), styleMask: .borderless, backing: .buffered, defer: true)
win.contentView!.addSubview(tf)
if let e = win.fieldEditor(true, for: tf) as? NSTextView { print("fieldEditor lineFragmentPadding", e.textContainer!.lineFragmentPadding, "containerInset", e.textContainerInset) }
