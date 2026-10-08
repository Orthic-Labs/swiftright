#if os(Windows)
import Foundation
import CUIA

/// Virtual-key SendInput. Never KEYEVENTF_UNICODE, so a real IME sees key events.
public enum VKInput {
    static let named: [String: (UInt16, Bool)] = [
        "ctrl": (0x11, false), "control": (0x11, false), "shift": (0x10, false), "alt": (0x12, false),
        "enter": (0x0D, false), "return": (0x0D, false), "tab": (0x09, false), "space": (0x20, false),
        "back": (0x08, false), "backspace": (0x08, false), "esc": (0x1B, false), "escape": (0x1B, false),
        "delete": (0x2E, true), "left": (0x25, true), "up": (0x26, true), "right": (0x27, true), "down": (0x28, true),
        "home": (0x24, true), "end": (0x23, true), "pageup": (0x21, true), "pagedown": (0x22, true),
    ]

    public static func vk(forName n: String) -> (UInt16, Bool)? {
        let k = n.lowercased()
        if let v = named[k] { return v }
        if k.count == 1, let c = k.utf16.first {
            if c >= 0x61 && c <= 0x7A { return (UInt16(c - 0x20), false) }   // a-z -> VK 0x41-0x5A
            if c >= 0x30 && c <= 0x39 { return (UInt16(c), false) }
        }
        if k.hasPrefix("f"), let n = Int(k.dropFirst()), (1...12).contains(n) { return (UInt16(0x70 + n - 1), false) }
        return nil
    }

    static func tap(_ vk: UInt16, ext: Bool) {
        _ = cuia_send_vk(vk, 0, ext ? 1 : 0)
        Thread.sleep(forTimeInterval: 0.03)
        _ = cuia_send_vk(vk, 1, ext ? 1 : 0)
        Thread.sleep(forTimeInterval: 0.03)
    }

    /// Chord such as "ctrl+shift+z" or "tab": modifiers down in order, final key tap, modifiers up in reverse.
    public static func chord(_ spec: String) throws {
        let parts = spec.split(separator: "+").map(String.init)
        var keys: [(UInt16, Bool)] = []
        for p in parts {
            guard let k = vk(forName: p) else { throw UIAError(what: "unknown key '\(p)'") }
            keys.append(k)
        }
        guard let last = keys.last else { return }
        let mods = keys.dropLast()
        for m in mods { _ = cuia_send_vk(m.0, 0, 0); Thread.sleep(forTimeInterval: 0.02) }
        tap(last.0, ext: last.1)
        for m in mods.reversed() { _ = cuia_send_vk(m.0, 1, 0); Thread.sleep(forTimeInterval: 0.02) }
    }

    /// Types text one UTF-16 unit at a time through the current layout's virtual keys (VkKeyScanW).
    /// A unit without a key on the layout (for example most CJK) throws: those need IME composition, not text injection.
    public static func type(_ text: String) throws {
        for u in text.utf16 {
            let r = cuia_vk_for_char(u)
            if r < 0 { throw UIAError(what: "no virtual key for U+\(String(u, radix: 16))") }
            let vk = UInt16(r & 0xFF), shift = (r >> 8) & 0xFF
            if shift & 1 != 0 { _ = cuia_send_vk(0x10, 0, 0) }
            if shift & 2 != 0 { _ = cuia_send_vk(0x11, 0, 0) }
            if shift & 4 != 0 { _ = cuia_send_vk(0x12, 0, 0) }
            tap(vk, ext: false)
            if shift & 4 != 0 { _ = cuia_send_vk(0x12, 1, 0) }
            if shift & 2 != 0 { _ = cuia_send_vk(0x11, 1, 0) }
            if shift & 1 != 0 { _ = cuia_send_vk(0x10, 1, 0) }
        }
    }

    public static let commandChords: [String: String] = [
        "copy": "ctrl+c", "paste": "ctrl+v", "undo": "ctrl+z", "redo": "ctrl+y", "selectAll": "ctrl+a",
    ]
}
#endif
