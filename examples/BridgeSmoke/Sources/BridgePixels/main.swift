import Foundation
import SwiftRightBridge

// BridgePixels (SR0 T4): a fixed scene whose RENDERED pixels scripts/drive-pixels.ps1 captures and asserts. It exists because
// BridgeSmoke commits an image and removes it again in the same turn (the lifetime check) and never uses a clip, so the final
// BridgeSmoke frame has no image and no clipped content to look at. BridgeSmoke itself is unchanged (its exe hash is in the tuple).
//
// Scene (DIP, multiplied by the window scale s; the driver reads the same numbers from the GEOM line):
//   bg        full-client rect F5F5F5
//   image A   4x4 RGBA gradient (cell i = (i*16, 255-i*16, 128)) scaled to 64x64 at (20,20), corner radius 8
//   image B   the same image, no radius, at (120,20)
//   text      "Marked text" at (20,120) with an underline D97706 (thickness max(1, 2s)) directly below the measured box, as an
//             IME marked-text run is drawn: underline x = text x, length = measured width
//   clip 1    clipPush(20,220,100,40), rect 20,220,300x40 C0392B, clipPop: only the 100 DIP wide part may show
//   clip 2    clipPush(200,230,100,20), rect 200,210,100x80 2E86C1, clipPop: only the 20 DIP tall band may show
//   clip 3    clipPush(340,20,32,64) around image C (64x64 at 340,20): only the left half of the image may show
//   translate translatePush(400,220), rect 0,0,60x40 27AE60, translatePop: must land at (400,220)
// Exit 0 when the scene was committed and the window ran for SWR_PIX_HOLD_S seconds (default 12); the pixel assertions live in the driver.

let env = ProcessInfo.processInfo.environment
let holdSeconds = Double(env["SWR_PIX_HOLD_S"] ?? "") ?? 12

let started = Date()
var ticks = 0
var finishing = false
var closed = false

/// stdout is block-buffered when piped (the driver reads it live), so every line is flushed.
func say(_ s: String) { Swift.print(s); fflush(stdout) }

func status(_ body: () throws -> Void) -> Int32 {
    do { try body(); return 0 } catch BridgeError.status(let rc, _) { return rc } catch { return -999 }
}

do {
    let bridge = try Bridge.load()
    bridge.onWindowClosed = {
        closed = true
        let b = bridge
        DispatchQueue.main.async { _ = try? b.shutdownComplete() }
    }
    bridge.onReady = { win in
        guard let m = try? win.metrics() else { say("metrics failed"); return }
        let s = m.scale
        say("ready: window=\(String(win.handle, radix: 16)) client=\(m.width)x\(m.height)px scale=\(m.scale)")
        var release: [TextRunHandle] = []
        var prims: [Primitive] = []
        // background
        prims.append(.rect(Rect(x: 0, y: 0, w: Float(m.width), h: Float(m.height)), color: 0xF5F5F5FF))
        // images
        var px: [UInt8] = []
        for i in 0..<16 { px += [UInt8(i * 16), UInt8(255 - i * 16), 128, 255] }
        var imageHandle: ImageHandle?
        _ = status { imageHandle = try bridge.registerImage(width: 4, height: 4, rgba: px) }
        if let img = imageHandle {
            prims.append(.image(img, Rect(x: 20 * s, y: 20 * s, w: 64 * s, h: 64 * s), radius: 8 * s))
            prims.append(.image(img, Rect(x: 120 * s, y: 20 * s, w: 64 * s, h: 64 * s)))
            prims.append(.clipPush(Rect(x: 340 * s, y: 20 * s, w: 32 * s, h: 64 * s)))
            prims.append(.image(img, Rect(x: 340 * s, y: 20 * s, w: 64 * s, h: 64 * s)))
            prims.append(.clipPop)
        } else { say("registerImage failed") }
        // text + underline
        if let t = try? bridge.measure(MeasureRequest(text: "Marked text", color: 0x1F1F1FFF, scale: s, maxWidth: 0)) {
            release.append(t.run)
            prims.append(.text(t.run, x: 20 * s, y: 120 * s))
            let ut = max(1, 2 * s)
            prims.append(.underline(Rect(x: 20 * s, y: 120 * s + t.height, w: t.width, h: ut), color: 0xD97706FF))
            say("GEOM text x=\(20 * s) y=\(120 * s) w=\(t.width) h=\(t.height) underline_y=\(120 * s + t.height) underline_h=\(ut)")
        } else { say("measure failed") }
        // clips
        prims.append(.clipPush(Rect(x: 20 * s, y: 220 * s, w: 100 * s, h: 40 * s)))
        prims.append(.rect(Rect(x: 20 * s, y: 220 * s, w: 300 * s, h: 40 * s), color: 0xC0392BFF))
        prims.append(.clipPop)
        prims.append(.clipPush(Rect(x: 200 * s, y: 230 * s, w: 100 * s, h: 20 * s)))
        prims.append(.rect(Rect(x: 200 * s, y: 210 * s, w: 100 * s, h: 80 * s), color: 0x2E86C1FF))
        prims.append(.clipPop)
        // translate
        prims.append(.translatePush(dx: 400 * s, dy: 220 * s))
        prims.append(.rect(Rect(x: 0, y: 0, w: 60 * s, h: 40 * s), color: 0x27AE60FF))
        prims.append(.translatePop)
        let node = NodeUpsert(id: 1, order: 1, bounds: Rect(x: 0, y: 0, w: Float(m.width), h: Float(m.height)), primitives: prims,
                              semantic: SemanticNode(role: .staticText, label: "BridgePixels scene", identifier: "pixels/scene"))
        let rc = status { try win.commit(Transaction(version: 1, upserts: [node])) }
        for r in release { bridge.release(r) }
        if let img = imageHandle { _ = bridge.release(img) }   // the committed node keeps the image alive
        say("COMMIT rc=\(statusName(rc)) scene committed s=\(s)")
        try? win.requestTicks(true)
    }
    bridge.onTick = { _, _ in
        ticks += 1
        if !finishing && Date().timeIntervalSince(started) > holdSeconds {
            finishing = true
            bridge.requestQuit()
        }
    }
    var runResult = "ok"
    do { try bridge.run(title: "SwiftRight BridgePixels", width: 640, height: 480) } catch { runResult = "run failed: \(error)" }
    let st = bridge.stats()
    say("renderer stats: paints=\(st.paints) commits=\(st.commits_accepted) rejected=\(st.commits_rejected) live_nodes=\(st.live_nodes) ticks=\(ticks) closed=\(closed)")
    say("run: \(runResult)")
    let ok = runResult == "ok" && st.commits_accepted >= 1 && st.commits_rejected == 0 && st.thread_violations == 0 && st.host_panics == 0
    say("PIXELS-HOST \(ok ? "PASS" : "FAIL")")
    exit(ok ? 0 : 1)
} catch BridgeError.startup(let message) {
    say(message); fflush(stdout); exit(78)
} catch {
    say("SWR_STARTUP_ERROR: \(error)"); exit(78)
}
