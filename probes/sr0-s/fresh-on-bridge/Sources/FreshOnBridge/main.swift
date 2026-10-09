import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// FreshOnBridge (SR0-S): fixtures F1-F9 on the fresh runtime through bridge ABI v0 (revision 0.3).
// Usage: FreshOnBridge.exe --fixture F1..F9 [--f3-variant list|vstack-<0|1|3>s] [--f9-variant notasks]
//                          [--reduced-motion-variant] --self-test
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
    if options.fixture == .F3 && options.f3Container == .lazy {
        print("SELFTEST \(options.label): BLOCKED (LazyVStack and ScrollView are absent from SwiftRightRuntime; no lazy container primitive exists to port the variant)")
        fflush(stdout)
        return 3
    }
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
    let test = SelfTest(bridge: bridge, backend: backend, model: model, log: log, engine: engine, options: options)
    test.requestQuit = { bridge.requestQuit() }
    backend.afterInput = { test.advance() }
    backend.afterClose = { test.windowClosed() }

    bridge.onReady = { win in MainActor.assumeIsolated { backend.ready(win) } }
    bridge.onEvent = { ev in MainActor.assumeIsolated { backend.handle(ev) } }
    bridge.onTick = { _, _ in MainActor.assumeIsolated { backend.tick(); test.tick() } }
    bridge.onWindowClosed = { MainActor.assumeIsolated { backend.closed() } }

    do {
        try bridge.run(title: "SwiftRight FreshOnBridge \(options.label)", width: 640, height: 480)
    } catch {
        print("run failed: \(error)")
        fflush(stdout)
        return 1
    }
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
