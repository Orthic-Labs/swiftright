import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// FreshOnBridge (SR0-S): fixtures F1-F9 on the fresh runtime through bridge ABI rev 0.4.
// Usage: FreshOnBridge.exe --fixture F1..F9 [--f3-variant list|vstack-<1|3>s|lazy-<1|3>s] [--f9-variant notasks]
//                          [--reduced-motion-variant] [--reduce-motion-override on|off] --self-test
//   --reduce-motion-override on|off  forces `accessibilityReduceMotion`. Without it animations run: the Windows "Animation
//                effects" setting is read and logged but does not decide (RESULT.md, 2026-10-10 parity pass).
//   --self-test  scripted run. Input (AX/UIA focus, VK keys, invoke, SetValue, window close) is driven from
//                outside by scripts/drive-fixture.ps1. Engine releases and model steps run in-process.
//   no flag      interactive run until the window closes.
// Exit: 0 = PASS, 1 = FAIL, 3 = BLOCKED (no failed assertion; at least one blocked), 78 = startup diagnostic.

func parseOptions(_ arguments: [String]) -> (FixtureOptions, String?) {
    var options = FixtureOptions()
    var label = "F1"
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--fixture":
            index += 1
            if index < arguments.count, let kind = FixtureKind(rawValue: arguments[index]) {
                options.fixture = kind
                label = kind.rawValue
            }
        case "--f3-variant":
            index += 1
            let name = index < arguments.count ? arguments[index] : ""
            switch name {
            case "list-0s": options.f3Container = .list; options.f3GapMs = 0
            case "list-1s": options.f3Container = .list; options.f3GapMs = 1000
            case "list-3s": options.f3Container = .list; options.f3GapMs = 3000
            case "vstack-1s": options.f3Container = .vstack; options.f3GapMs = 1000
            case "vstack-3s": options.f3Container = .vstack; options.f3GapMs = 3000
            case "lazy-1s": options.f3Container = .lazy; options.f3GapMs = 1000
            case "lazy-3s": options.f3Container = .lazy; options.f3GapMs = 3000
            default: return (options, "invalid --f3-variant \(name)")
            }
            label = "F3 \(name)"
        case "--f9-variant":
            index += 1
            if index < arguments.count, arguments[index] == "notasks" {
                options.f9NoTasks = true
                label = "F9 notasks"
            }
        case "--reduced-motion-variant":
            options.reducedVariant = true
            label = "F6-reduced"
        case "--release-event":
            index += 1
            options.releaseEvent = index < arguments.count ? arguments[index] : nil
        case "--release-file":
            index += 1
            options.releaseFile = index < arguments.count ? arguments[index] : nil
        case "--f7-live":
            options.f7Live = true
            label = "F7"
        case "--ready-file":
            index += 1
            options.readyFile = index < arguments.count ? arguments[index] : nil
        case "--reduce-motion-override":
            index += 1
            let value = index < arguments.count ? arguments[index] : ""
            switch value {
            case "on": options.reduceMotionOverride = true; label = "F6 override-on"
            case "off": options.reduceMotionOverride = false; label = "F6 override-off"
            default: return (options, "invalid --reduce-motion-override \(value)")
            }
        default:
            break
        }
        index += 1
    }
    options.label = label
    return (options, nil)
}

@MainActor
func runFreshOnBridge(options: FixtureOptions) -> Int32 {
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

    let log = EventLog()
    let engine = FakeEngine(log: log)
    let model = RowModel(fixtureNumber: options.fixture.number, log: log, engine: engine, reducedMotion: options.reducedVariant)
    let backend = BridgeBackend(bridge: bridge, model: model, log: log, options: options)
    bridge.textStore = FreshTextStore(backend: backend)
    let hooks = AutomationHooks(options: options, engine: engine, backend: backend, log: log)
    let test = SelfTest(bridge: bridge, backend: backend, model: model, log: log, engine: engine, options: options,
                        hooks: hooks)
    test.requestQuit = { bridge.requestQuit() }
    backend.afterInput = { test.advance() }
    backend.afterClose = { test.windowClosed() }

    hooks.start()
    bridge.onReady = { win in MainActor.assumeIsolated { backend.ready(win) } }
    bridge.onEvent = { ev in MainActor.assumeIsolated { backend.handle(ev) } }
    bridge.onTick = { _, timestamp in MainActor.assumeIsolated { backend.tick(timestampNS: timestamp); hooks.poll(); test.tick() } }
    bridge.onWindowClosed = { MainActor.assumeIsolated { backend.closed() } }

    do {
        try bridge.run(title: "SwiftRight FreshOnBridge \(options.label)", width: 640, height: 480)
    } catch {
        print("run failed: \(error)")
        fflush(stdout)
        return 1
    }
    test.finishAfterRun()
    if !test.finished {
        print("SELFTEST \(options.label): FAIL (run ended before the self-test finished)")
        fflush(stdout)
        return 1
    }
    return test.exitCode
}

let (parsed, parseError) = parseOptions(CommandLine.arguments)
if let parseError {
    print("SELFTEST \(parsed.label): FAIL (\(parseError))")
    exit(2)
}
let status = MainActor.assumeIsolated { runFreshOnBridge(options: parsed) }
fflush(stdout)
exit(status)
