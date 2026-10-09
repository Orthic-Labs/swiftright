import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// SR1Gallery (SR1 head start, Windows backend): one control screen on the fresh runtime, drawn by the Windows
// renderer through bridge ABI 0.5.
//
// Usage: SR1Gallery.exe --screen <name> [--self-test] [--live-modal]
//   --screen <name>  toggle image editor label list-single list-multi list-delete menu alert dialog shortcut disabled
//   --self-test      scripted checks against the runtime API and the commit records. Input is injected in-process
//                    through Graph (no AX/VK driver needed). The self-test never opens a MessageBox.
//   --live-modal     interactive runs only: alert and dialog plans open a MessageBoxW (YES/NO or OK/Cancel).
//   no flag          interactive run until the window closes.
// Exit: 0 = PASS, 1 = FAIL, 3 = BLOCKED (no failed check; at least one check the ABI cannot verify), 2 = usage,
//       78 = startup diagnostic (SWR_STARTUP_ERROR, from the bridge loader).

struct GalleryOptions {
    var screen = "toggle"
    var selfTest = false
    var liveModal = false
}

func parseGalleryOptions(_ arguments: [String]) -> (GalleryOptions, String?) {
    var options = GalleryOptions()
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--screen":
            index += 1
            guard index < arguments.count, gallerySceneNames.contains(arguments[index]) else {
                return (options, "invalid --screen \(index < arguments.count ? arguments[index] : "(missing)")")
            }
            options.screen = arguments[index]
        case "--self-test":
            options.selfTest = true
        case "--live-modal":
            options.liveModal = true
        default:
            return (options, "unknown argument \(arguments[index])")
        }
        index += 1
    }
    return (options, nil)
}

@MainActor
func runGallery(_ options: GalleryOptions) -> Int32 {
    let bridge: Bridge
    do {
        bridge = try Bridge.load()
    } catch BridgeError.startup(let message) {
        print(message)
        return 78
    } catch {
        print("SWR_STARTUP_ERROR: \(error)")
        return 78
    }

    let model = GalleryModel()
    let backend = GalleryBackend(bridge: bridge, model: model, screen: options.screen, liveModal: options.liveModal)
    let test = options.selfTest ? GallerySelfTest(backend: backend, model: model, screen: options.screen) : nil
    test?.requestQuit = { bridge.requestQuit() }
    backend.afterInput = { test?.advance() }
    backend.afterClose = { test?.windowClosed() }

    bridge.onReady = { win in MainActor.assumeIsolated { backend.ready(win) } }
    bridge.onEvent = { ev in MainActor.assumeIsolated { backend.handle(ev) } }
    bridge.onTick = { _, timestamp in
        MainActor.assumeIsolated {
            backend.tick(timestampNS: timestamp)
            test?.advance()
        }
    }
    bridge.onWindowClosed = { MainActor.assumeIsolated { backend.closed() } }

    do {
        try bridge.run(title: "SR1 Gallery \(options.screen)", width: 640, height: 480)
    } catch {
        print("run failed: \(error)")
        fflush(stdout)
        return 1
    }
    guard let test else { return 0 }
    if !test.finished {
        print("SELFTEST SR1 \(options.screen): FAIL (run ended before the self-test finished)")
        fflush(stdout)
        return 1
    }
    return test.exitCode
}

let (parsed, parseError) = parseGalleryOptions(CommandLine.arguments)
if let parseError {
    print("SELFTEST SR1 \(parsed.screen): FAIL (\(parseError))")
    exit(2)
}
let status = MainActor.assumeIsolated { runGallery(parsed) }
fflush(stdout)
exit(status)
