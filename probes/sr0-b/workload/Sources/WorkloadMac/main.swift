import AppKit
import SwiftUI
import QuartzCore
import WorkloadCore

// WorkloadMac: the SR0 section 11 workload as a real SwiftUI app (one Window scene), macOS side.
//
// Usage (normally launched by SckRecorder, which also posts the input script and captures the window):
//   WorkloadMac --run-id r1 --out <dir> [--warmup-s 10] [--measure-s 60] [--instr full|light] [--ready-file <path>]
//   WorkloadMac --model-selftest <seconds>   headless model check, no window (safe to run anywhere)
//   WorkloadMac --overhead                   timer micro-benchmark only, no window
//
// The app is self-timed: 10 s warm-up, 60 s measured run, then window close (F9-style teardown), then
// integrity.json / meta.json / raw CSVs are written and the process exits. All timestamps are CLOCK_UPTIME_RAW
// nanoseconds (the mach_absolute_time domain the recorder uses).

let args = WorkloadArgs(CommandLine.arguments)

if let secs = args.options["model-selftest"], let seconds = Double(secs) {
    Task { @MainActor in
        let (integrity, failures) = await WorkloadModel.headlessSelfTest(seconds: seconds)
        print(WorkloadModel.integrityJSON(integrity))
        if failures.isEmpty {
            print("MODEL-SELFTEST PASS (\(seconds) s synthetic)")
            exit(0)
        }
        for f in failures { print("MODEL-SELFTEST FAIL: \(f)") }
        exit(1)
    }
    dispatchMain()
}

if args.options["overhead"] != nil {
    let r = RunRecorder()
    OverheadBench.run(into: r)
    for o in r.overhead { print("\(o.name): \(o.nsPerPair) ns (n=\(o.iterations))") }
    exit(0)
}

@MainActor
final class MacHost: NSObject {
    static let shared = MacHost()

    let recorder = RunRecorder()
    let model: WorkloadModel
    var sampler: MainActorSampler?
    var link: CADisplayLink?
    weak var window: NSWindow?
    var attached = false
    var readyWritten = false
    var finished = false
    var attachTicks: UInt64 = 0
    var frames = 0

    override init() {
        model = WorkloadModel(config: args.config, recorder: recorder)
        super.init()
    }

    func attach(_ w: NSWindow) {
        guard !attached else { return }
        attached = true
        window = w
        attachTicks = WClock.ticks()
        w.styleMask.remove(.resizable)
        if let screen = w.screen ?? NSScreen.main {
            w.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 40))
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        OverheadBench.run(into: recorder)
        if let view = w.contentView {
            let l = view.displayLink(target: self, selector: #selector(frame(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        if args.config.instr == .full {
            let s = MainActorSampler(recorder: recorder)
            s.start()
            sampler = s
        }
        for delay in [0.3, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MacHost.shared.model.focusActive() }
        }
    }

    @objc func frame(_ link: CADisplayLink) {
        guard !finished else { return }
        frames += 1
        let now = WClock.ticks()
        if !readyWritten {
            // The run clock starts only after the window has settled: counter region known, focus applied.
            if WClock.seconds(now &- attachTicks) >= 2.5, model.counterRect.w > 0 {
                writeReady()
            } else {
                return
            }
        }
        model.advance(nowTicks: now)
        if model.phase(nowTicks: now) == .finished {
            finish()
        }
    }

    func writeReady() {
        readyWritten = true
        guard let w = window else { return }
        let screen = w.screen ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let mode = CGDisplayCopyDisplayMode(displayID)
        let info: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "window_number": w.windowNumber,
            "window_frame_screen": ["x": w.frame.minX, "y": w.frame.minY, "w": w.frame.width, "h": w.frame.height],
            "content_size_pt": ["w": Double(w.contentLayoutRect.width), "h": Double(w.contentLayoutRect.height)],
            "scale": Double(w.backingScaleFactor),
            "counter_rect_pt": ["x": model.counterRect.x, "y": model.counterRect.y, "w": model.counterRect.w, "h": model.counterRect.h],
            "display_id": Int(displayID),
            "display_refresh_hz": mode?.refreshRate ?? 0,
            "display_pixels": ["w": mode?.pixelWidth ?? 0, "h": mode?.pixelHeight ?? 0],
            "run_id": args.config.runID,
            "instr": args.config.instr.rawValue,
            "warmup_s": args.config.warmupS,
            "measure_s": args.config.measureS,
            "clock": WClock.name,
            "ready_ticks": Int(WClock.ticks()),
        ]
        let path = args.options["ready-file"] ?? (args.config.outDir + "/ready.json")
        try? FileManager.default.createDirectory(atPath: args.config.outDir, withIntermediateDirectories: true)
        try? jsonString(info).write(toFile: path, atomically: true, encoding: .utf8)
    }

    func finish() {
        finished = true
        link?.invalidate()
        sampler?.stop()
        let dir = args.config.outDir
        model.close()
        window?.close()
        // Late engine results and cancelled tasks drain over the next run-loop turns; counted, never committed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MacHost.shared.writeOutputs(dir: dir) }
    }

    func writeOutputs(dir: String) {
        recorder.write(dir: dir)
        let i = model.finalIntegrity()
        let extra: [String: Any] = ["app_exit": "complete", "run_id": args.config.runID, "frames_driven": frames]
        try? WorkloadModel.integrityJSON(i, extra: extra).write(toFile: dir + "/integrity.json", atomically: true, encoding: .utf8)
        let meta: [String: Any] = [
            "run_id": args.config.runID,
            "platform": "macos",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "instr": args.config.instr.rawValue,
            "clock": WClock.name,
            "hz": Int(WClock.hz),
            "t0_ticks": Int(model.t0),
            "measure_start_ticks": Int(model.measureStartTicks),
            "measure_end_ticks": Int(model.measureEndTicks),
            "warmup_s": args.config.warmupS,
            "measure_s": args.config.measureS,
            "seed": String(args.config.seed),
            "window_pt": ["w": 960, "h": 640],
            "total_rows": args.config.totalRows,
            "release_build": !isDebugBuild,
        ]
        try? jsonString(meta).write(toFile: dir + "/meta.json", atomically: true, encoding: .utf8)
        print("WORKLOAD-MAC-DONE run=\(args.config.runID) dir=\(dir)")
        fflush(stdout)
        NSApp.terminate(nil)
    }
}

#if DEBUG
let isDebugBuild = true
#else
let isDebugBuild = false
#endif

final class GrabView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { MacHost.shared.attach(w) } }
    }
}

struct WindowGrabber: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GrabView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct WorkloadApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("SR0 Workload", id: "main") {
            WorkloadRoot(model: MacHost.shared.model)
                .frame(width: 960, height: 640)
                .background(WindowGrabber())
        }
        .windowResizability(.contentSize)
    }
}

WorkloadApp.main()
