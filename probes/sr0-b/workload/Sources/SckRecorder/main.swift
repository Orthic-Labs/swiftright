import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import QuartzCore
import ScreenCaptureKit

// SckRecorder: separate-process input poster and visible-response recorder for the macOS SR0 workload
// (CONTRACT section 5: "input event timestamp from the injecting recorder (mach absolute time) to the first frame
// containing the response, detected by ScreenCaptureKit frame timestamps on a recorder-owned stream").
//
//   SckRecorder --app <WorkloadMac executable> --out <dir> [--run-id r1] [--warmup-s 10] [--measure-s 60]
//               [--rate-hz 10] [--instr full|light] [--calib-flips 120] [--calibrate-only] [--request-permissions]
//
// BUILD-ONLY IN THIS LANE: nothing here has been run. It needs, for the signed/ad-hoc identity that runs it
// (scripts/package-mac.sh makes SckRecorder.app): Screen Recording and Accessibility (post events) grants, granted
// by the Mac test user once, interactively. It opens a small calibration window and launches the workload app.
//
// Clocks. Everything is CLOCK_UPTIME_RAW nanoseconds (mach_absolute_time with the timebase applied). Key posts are
// stamped immediately before CGEvent.postToPid. SCStream frames carry SCStreamFrameInfo.displayTime (mach host time
// of the display); that is the response endpoint, never the arrival time of the callback.
//
// Calibration (mandatory; the analyzer refuses PASS without calibration.csv): the recorder flips a window of its OWN
// between black and white 120 times, stamps each flip request, captures that window through the same kind of stream,
// and records request-to-displayTime of the first changed frame. That floor is the best case of the whole
// post/compose/capture path for a trivial layer; it is reported next to the app latencies and gates validity.
//
// Output (all under --out):
//   calibration.csv   flip_seq,t_flip_ns,display_ns,latency_ms,arrival_ns
//   keys.csv          seq,char,t_post_ns,t_display_ns,latency_ms,status      (status: ok | timeout | overlap)
//   frames_display.csv display_ns of every complete frame captured for the app window (Mac frame-interval proxy)
//   recorder_meta.json permission state, display refresh, scale, crop rect, frame size, thresholds, noise floor,
//                      calibration summary, region self-check
//   app/              the workload app's own outputs (inputs.csv, mainactor.csv, integrity.json, meta.json, ...)

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - clock

struct MachClock {
    static let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()
    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    static func ns(fromMachTicks t: UInt64) -> UInt64 { t &* UInt64(timebase.numer) / UInt64(timebase.denom) }
}

// MARK: - args

var opts: [String: String] = [:]
do {
    let a = CommandLine.arguments
    var i = 1
    while i < a.count {
        if a[i].hasPrefix("--") {
            let key = String(a[i].dropFirst(2))
            if i + 1 < a.count, !a[i + 1].hasPrefix("--") { opts[key] = a[i + 1]; i += 1 } else { opts[key] = "1" }
        }
        i += 1
    }
}
let outDir = opts["out"] ?? "./sr0-workload-mac-out"
let runID = opts["run-id"] ?? "r1"
let warmupS = Double(opts["warmup-s"] ?? "") ?? 10
let measureS = Double(opts["measure-s"] ?? "") ?? 60
let rateHz = Double(opts["rate-hz"] ?? "") ?? 10
let instr = opts["instr"] ?? "full"
let calibFlips = Int(opts["calib-flips"] ?? "") ?? 120
let appPath = opts["app"]
let calibrateOnly = opts["calibrate-only"] != nil
/// Keys are posted only until this long before the app's measured window ends: a key posted while the app closes its window is
/// lost by design and is not an edit the run owes (the Windows harness stops its script the same way, `key_tail_s`).
let keyTailS = Double(opts["key-tail-s"] ?? "") ?? 0.5
/// Smallest changed-pixel count that counts as the counter text having changed (per-channel difference > 24). One digit of 13 pt text
/// on a 1x display changes on the order of 20-60 pixels; the static region has a noise floor of 0 (measured and reported per run).
let minResponsePx = Int(opts["min-response-px"] ?? "") ?? 12

// Keys: the same cycle as the Windows script ("mwqogdhbnk"), US ANSI virtual key codes.
let keyChars: [Character] = Array("mwqogdhbnk")
let keyCodes: [CGKeyCode] = [0x2E, 0x0D, 0x0C, 0x1F, 0x05, 0x02, 0x04, 0x0B, 0x2D, 0x28]

func writeText(_ path: String, _ text: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
}

func json(_ d: [String: Any]) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys, .prettyPrinted])) ?? Data(), as: UTF8.self)
}

func percentile(_ v: [Double], _ p: Double) -> Double {
    guard !v.isEmpty else { return .nan }
    let s = v.sorted()
    let rank = max(1, min(s.count, Int((p * Double(s.count)).rounded(.up))))
    return s[rank - 1]
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

// MARK: - frame sink

/// One captured frame, reduced to what the detectors need.
struct FrameSample {
    var displayNS: UInt64
    var arrivalNS: UInt64
    var width: Int
    var height: Int
    var region: [UInt8]      // BGRA bytes of the crop (rows tightly packed)
    var cropW: Int
    var cropH: Int
    var luma: Double         // mean luma of the center patch (calibration)
}

final class StreamSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var crop: CGRect          // pixels, origin top-left of the captured image
    var onFrame: (FrameSample) -> Void
    var stopped = false
    /// When set, the next complete frame is written to this path as a PNG (full captured window) with the crop rectangle outlined.
    /// Verifies the response-region crop against the pixels actually captured; never used for detection.
    var snapshotPath: String?
    private(set) var framesSeen = 0
    private(set) var lastWidth = 0
    private(set) var lastHeight = 0
    private(set) var errors: [String] = []

    init(crop: CGRect, onFrame: @escaping (FrameSample) -> Void) {
        self.crop = crop
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        let arrival = MachClock.now()
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first else { return }
        if let raw = info[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != .complete { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var displayNS = arrival
        if let t = info[.displayTime] as? UInt64 {
            displayNS = MachClock.ns(fromMachTicks: t)
        } else if let n = info[.displayTime] as? NSNumber {
            displayNS = MachClock.ns(fromMachTicks: n.uint64Value)
        } else {
            // Fallback: the buffer's presentation time is host time in seconds.
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if pts.isValid { displayNS = UInt64(CMTimeGetSeconds(pts) * 1_000_000_000) }
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        framesSeen += 1
        lastWidth = w
        lastHeight = h
        if let path = snapshotPath {
            snapshotPath = nil
            writeSnapshot(path: path, base: base, width: w, height: h, stride: stride)
        }
        let x0 = max(0, min(w - 1, Int(crop.minX)))
        let y0 = max(0, min(h - 1, Int(crop.minY)))
        let cw = max(1, min(w - x0, Int(crop.width)))
        let ch = max(1, min(h - y0, Int(crop.height)))
        var region = [UInt8](repeating: 0, count: cw * ch * 4)
        region.withUnsafeMutableBytes { dst in
            for row in 0..<ch {
                memcpy(dst.baseAddress! + row * cw * 4, base + (y0 + row) * stride + x0 * 4, cw * 4)
            }
        }
        // Center 32x32 patch mean luma (calibration window detection).
        var sum = 0.0
        var n = 0
        let px0 = max(0, w / 2 - 16), py0 = max(0, h / 2 - 16)
        for y in py0..<min(h, py0 + 32) {
            let rowPtr = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in px0..<min(w, px0 + 32) {
                let p = rowPtr + x * 4
                sum += (Double(p[0]) + Double(p[1]) + Double(p[2])) / 3
                n += 1
            }
        }
        onFrame(FrameSample(displayNS: displayNS, arrivalNS: arrival, width: w, height: h, region: region,
                            cropW: cw, cropH: ch, luma: n > 0 ? sum / Double(n) : 0))
    }

    private func writeSnapshot(path: String, base: UnsafeMutableRawPointer, width: Int, height: Int, stride: Int) {
        guard let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(1)
        // CGContext origin is bottom-left; the crop is top-left based.
        ctx.stroke(CGRect(x: crop.minX, y: CGFloat(height) - crop.maxY, width: crop.width, height: crop.height))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        errors.append("stream stopped: \(error)")
        stopped = true
    }
}

func makeStream(windowID: CGWindowID, widthPx: Int, heightPx: Int, sink: StreamSink, queue: DispatchQueue) async throws -> SCStream {
    var window: SCWindow?
    for _ in 0..<50 {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        window = content.windows.first { $0.windowID == windowID }
        if window != nil { break }
        try await Task.sleep(nanoseconds: 200_000_000)
    }
    guard let window else { throw NSError(domain: "SckRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "SCWindow \(windowID) not found"]) }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    config.width = widthPx
    config.height = heightPx
    config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    config.queueDepth = 6
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false
    config.capturesAudio = false
    config.scalesToFit = false
    config.ignoreShadowsSingleWindow = true
    let stream = SCStream(filter: filter, configuration: config, delegate: sink)
    try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
    return stream
}

// MARK: - calibration (recorder-owned flipping window)

final class CalibrationResult {
    var rows: [(seq: Int, tFlip: UInt64, display: UInt64, latencyMS: Double, arrival: UInt64)] = []
    var missed = 0
    var framesSeen = 0
    var error = ""
}

@MainActor
func runCalibration(flips: Int) async -> CalibrationResult {
    let result = CalibrationResult()
    let rect = NSRect(x: 80, y: 120, width: 220, height: 160)
    let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = true
    window.level = .floating
    window.backgroundColor = .black
    let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.black.cgColor
    window.contentView = view
    window.orderFrontRegardless()
    let scale = window.backingScaleFactor
    let lock = NSLock()
    var frames: [FrameSample] = []
    let sink = StreamSink(crop: CGRect(x: 0, y: 0, width: 4, height: 4)) { f in
        lock.lock(); frames.append(f); lock.unlock()
    }
    let queue = DispatchQueue(label: "sr0.calibration.frames", qos: .userInteractive)
    let stream: SCStream
    do {
        try await Task.sleep(nanoseconds: 400_000_000)
        stream = try await makeStream(windowID: CGWindowID(window.windowNumber), widthPx: Int(rect.width * scale),
                                      heightPx: Int(rect.height * scale), sink: sink, queue: queue)
    } catch {
        result.error = "calibration stream failed: \(error)"
        window.close()
        return result
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    var flipTimes: [(seq: Int, t: UInt64, white: Bool)] = []
    var white = false
    for seq in 0..<flips {
        white.toggle()
        let target = white
        let t = MachClock.now()
        view.layer?.backgroundColor = (target ? NSColor.white : NSColor.black).cgColor
        CATransaction.flush()
        flipTimes.append((seq, t, target))
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    try? await Task.sleep(nanoseconds: 400_000_000)
    try? await stream.stopCapture()
    window.close()
    let all = lock.withLock { frames }
    result.framesSeen = all.count
    for flip in flipTimes {
        // First frame displayed after the request whose luma is on the new side of mid-grey.
        if let f = all.first(where: { $0.displayNS > flip.t && (flip.white ? $0.luma > 128 : $0.luma < 128) }) {
            result.rows.append((flip.seq, flip.t, f.displayNS, Double(f.displayNS &- flip.t) / 1_000_000, f.arrivalNS))
        } else {
            result.missed += 1
        }
    }
    return result
}

// MARK: - recorder for the app window

struct PendingKey {
    var seq: Int
    var ch: Character
    var tPost: UInt64
    var ref: [UInt8]
}

final class KeyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var history: [(display: UInt64, region: [UInt8])] = []
    private var pending: [PendingKey] = []
    var resolved: [(seq: Int, ch: Character, tPost: UInt64, tDisplay: UInt64, status: String, diffPx: Int)] = []
    var frameDisplayNS: [UInt64] = []
    /// FNV-1a of the response-region bytes of every frame (frames_display.csv column `region_hash`): independent re-matching of
    /// distinct counter states to keys, and proof of how many distinct states the region showed.
    var frameRegionHash: [UInt64] = []
    var threshold: Int
    private(set) var noiseMax = 0
    /// Every frame-to-frame changed-pixel count of the static response region while no key was posted.
    private(set) var noiseSeries: [Int] = []
    var collectingNoise = false
    private var lastNoiseRegion: [UInt8]?

    init(threshold: Int) { self.threshold = threshold }

    static func diffPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return Int.max }
        var n = 0
        var i = 0
        while i + 3 < a.count {
            let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
            if d > 24 { n += 1 }
            i += 4
        }
        return n
    }

    func onFrame(_ f: FrameSample) {
        lock.lock(); defer { lock.unlock() }
        frameDisplayNS.append(f.displayNS)
        var h: UInt64 = 0xcbf29ce484222325
        for b in f.region { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        frameRegionHash.append(h)
        if collectingNoise {
            if let last = lastNoiseRegion {
                let d = Self.diffPixels(last, f.region)
                noiseSeries.append(d)
                noiseMax = max(noiseMax, d)
            }
            lastNoiseRegion = f.region
        }
        history.append((f.displayNS, f.region))
        if history.count > 16 { history.removeFirst() }
        guard !pending.isEmpty else { return }
        var i = 0
        while i < pending.count {
            let key = pending[i]
            let diff = f.displayNS > key.tPost ? Self.diffPixels(key.ref, f.region) : 0
            if f.displayNS > key.tPost, diff >= threshold {
                resolved.append((key.seq, key.ch, key.tPost, f.displayNS, "ok", diff))
                pending.remove(at: i)
                // Every other pending key now needs a LATER change than this frame.
                for j in 0..<pending.count where pending[j].tPost < f.displayNS { pending[j].ref = f.region }
                continue
            }
            if MachClock.now() > key.tPost + 1_000_000_000 {
                resolved.append((key.seq, key.ch, key.tPost, 0, "timeout", diff))
                pending.remove(at: i)
                continue
            }
            i += 1
        }
    }

    /// Registers a key about to be posted. The reference is the latest frame displayed at or before the post time.
    func willPost(seq: Int, ch: Character, tPost: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let ref = history.last(where: { $0.display <= tPost })?.region ?? history.last?.region ?? []
        if !pending.isEmpty { resolved.append((-1, ch, tPost, 0, "overlap-note", 0)) }
        pending.append(PendingKey(seq: seq, ch: ch, tPost: tPost, ref: ref))
    }

    func flushTimeouts() {
        lock.lock(); defer { lock.unlock() }
        for key in pending { resolved.append((key.seq, key.ch, key.tPost, 0, "timeout", 0)) }
        pending.removeAll()
    }

    var snapshot: (resolved: [(seq: Int, ch: Character, tPost: UInt64, tDisplay: UInt64, status: String, diffPx: Int)], frames: [UInt64], hashes: [UInt64]) {
        lock.lock(); defer { lock.unlock() }
        return (resolved, frameDisplayNS, frameRegionHash)
    }
}

// MARK: - permissions

func preflight() -> [String: Any] {
    var state: [String: Any] = [:]
    state["screen_capture_access"] = CGPreflightScreenCaptureAccess()
    state["post_event_access"] = CGPreflightPostEventAccess()
    state["ax_trusted"] = AXIsProcessTrusted()
    return state
}

// MARK: - main flow

@MainActor
func run() async -> Int32 {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    var meta: [String: Any] = [
        "run_id": runID, "platform": "macos-recorder", "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "warmup_s": warmupS, "measure_s": measureS, "rate_hz": rateHz, "instr": instr, "clock": "mach-uptime-ns",
        "sck_frame_info": "SCStreamFrameInfo.displayTime (mach host time of the display)",
        "key_chars": String(keyChars),
    ]
    var perms = preflight()
    if opts["request-permissions"] != nil {
        if !(perms["screen_capture_access"] as? Bool ?? false) { _ = CGRequestScreenCaptureAccess() }
        if !(perms["post_event_access"] as? Bool ?? false) { _ = CGRequestPostEventAccess() }
        perms = preflight()
    }
    meta["permissions"] = perms
    guard (perms["screen_capture_access"] as? Bool) == true, (perms["post_event_access"] as? Bool) == true else {
        meta["blocked"] = "missing Screen Recording and/or post-event (Accessibility) permission for this identity"
        writeText(outDir + "/recorder_meta.json", json(meta))
        print("RECORDER-BLOCKED \(meta["blocked"]!). Grant them to SckRecorder.app in System Settings > Privacy & Security, then rerun.")
        return 3
    }

    // 1) calibration
    print("RECORDER-CALIBRATING flips=\(calibFlips)")
    let calib = await runCalibration(flips: calibFlips)
    let lat = calib.rows.map(\.latencyMS)
    var calibSummary: [String: Any] = [
        "flips": calibFlips, "detected": calib.rows.count, "missed": calib.missed, "frames_seen": calib.framesSeen,
        "p50_ms": percentile(lat, 0.5), "p95_ms": percentile(lat, 0.95), "p99_ms": percentile(lat, 0.99),
        "max_ms": lat.max() ?? .nan, "error": calib.error,
    ]
    writeText(outDir + "/calibration.csv", "flip_seq,t_flip_ns,display_ns,latency_ms,arrival_ns\n" +
        calib.rows.map { "\($0.seq),\($0.tFlip),\($0.display),\($0.latencyMS),\($0.arrival)" }.joined(separator: "\n") + "\n")
    let calibOK = calib.error.isEmpty && calib.rows.count >= Int(Double(calibFlips) * 0.9)
    calibSummary["valid"] = calibOK
    meta["calibration"] = calibSummary
    print("RECORDER-CALIBRATION valid=\(calibOK) detected=\(calib.rows.count)/\(calibFlips) p50=\(percentile(lat, 0.5)) ms p95=\(percentile(lat, 0.95)) ms")
    if calibrateOnly || !calibOK || appPath == nil {
        writeText(outDir + "/recorder_meta.json", json(meta))
        return calibOK ? 0 : 4
    }

    // 2) launch the workload app
    let appOut = outDir + "/app"
    try? FileManager.default.createDirectory(atPath: appOut, withIntermediateDirectories: true)
    let readyPath = appOut + "/ready.json"
    try? FileManager.default.removeItem(atPath: readyPath)
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: appPath!)
    proc.arguments = ["--run-id", runID, "--out", appOut, "--warmup-s", "\(warmupS)", "--measure-s", "\(measureS)", "--instr", instr,
                      "--ready-file", readyPath]
    let logHandle = FileHandle(forWritingAtPath: appOut + "/stdout.txt") ?? {
        FileManager.default.createFile(atPath: appOut + "/stdout.txt", contents: nil)
        return FileHandle(forWritingAtPath: appOut + "/stdout.txt")!
    }()
    proc.standardOutput = logHandle
    proc.standardError = logHandle
    do { try proc.run() } catch {
        meta["blocked"] = "app launch failed: \(error)"
        writeText(outDir + "/recorder_meta.json", json(meta))
        return 5
    }
    let pid = proc.processIdentifier
    meta["app_pid"] = Int(pid)

    var ready: [String: Any]?
    let readyDeadline = Date().addingTimeInterval(45)
    while Date() < readyDeadline, ready == nil, proc.isRunning {
        try? await Task.sleep(nanoseconds: 250_000_000)
        if let data = FileManager.default.contents(atPath: readyPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { ready = obj }
    }
    guard let ready else {
        meta["blocked"] = "app never wrote ready.json"
        writeText(outDir + "/recorder_meta.json", json(meta))
        if proc.isRunning { proc.terminate() }
        return 6
    }
    meta["app_ready"] = ready
    let scale = (ready["scale"] as? Double) ?? 2
    let frameRect = ready["window_frame_screen"] as? [String: Double] ?? [:]
    let content = ready["content_size_pt"] as? [String: Double] ?? [:]
    let counter = ready["counter_rect_pt"] as? [String: Double] ?? [:]
    let winW = frameRect["w"] ?? 960, winH = frameRect["h"] ?? 668
    let titlebar = max(0, winH - (content["h"] ?? winH))
    let pad = 3.0
    // ready.json reports the counter at "typed 0"; the label grows a digit at 10, 100 and 1000 keys (about 600 per run), and the text is
    // leading-aligned with empty space to its right, so the crop extends to the right by room for four more digits.
    let counterGrowthPt = 40.0
    // `counter_rect_pt` is SwiftUI's `.global` frame, which is already in window coordinates (title bar included: the counter sits at
    // y = 28 + 12). Adding the title bar again put the crop on the editor field below the counter (window.png shows the outline).
    let crop = CGRect(x: ((counter["x"] ?? 0) - pad) * scale, y: ((counter["y"] ?? 0) - pad) * scale,
                      width: ((counter["w"] ?? 60) + 2 * pad + counterGrowthPt) * scale, height: ((counter["h"] ?? 20) + 2 * pad) * scale)
    meta["crop_px"] = ["x": crop.minX, "y": crop.minY, "w": crop.width, "h": crop.height]
    meta["titlebar_pt"] = titlebar

    // 3) capture stream on the app window
    let tracker = KeyTracker(threshold: minResponsePx)
    let sink = StreamSink(crop: crop) { f in tracker.onFrame(f) }
    let queue = DispatchQueue(label: "sr0.app.frames", qos: .userInteractive)
    let stream: SCStream
    do {
        stream = try await makeStream(windowID: CGWindowID((ready["window_number"] as? Int) ?? 0),
                                      widthPx: Int(winW * scale), heightPx: Int(winH * scale), sink: sink, queue: queue)
    } catch {
        meta["blocked"] = "app capture failed: \(error)"
        writeText(outDir + "/recorder_meta.json", json(meta))
        if proc.isRunning { proc.terminate() }
        return 7
    }
    // Noise floor of the response region with no input (the region is static text; caret blink is outside it).
    sink.snapshotPath = outDir + "/window.png"
    try? await Task.sleep(nanoseconds: 800_000_000)      // settle: the first captured frames can predate the window's final drawing
    tracker.collectingNoise = true
    try? await Task.sleep(nanoseconds: 1_700_000_000)
    tracker.collectingNoise = false
    let noise = tracker.noiseMax
    tracker.threshold = max(minResponsePx, noise * 3)
    meta["noise_floor_px"] = noise
    meta["noise_series_px"] = tracker.noiseSeries
    meta["response_threshold_px"] = tracker.threshold
    meta["captured_size_px"] = ["w": sink.lastWidth, "h": sink.lastHeight]
    meta["expected_size_px"] = ["w": Int(winW * scale), "h": Int(winH * scale)]

    // 4) post the script until the app exits
    let startNS = MachClock.now() + 300_000_000
    // The app's run clock starts at the frame that wrote ready.json (t0 is that frame's tick, a few ms before ready_ticks).
    let readyTicks = UInt64(max(0, (ready["ready_ticks"] as? Int) ?? 0))
    let keyDeadlineNS: UInt64 = readyTicks > 0 ? readyTicks + UInt64(max(0, warmupS + measureS - keyTailS) * 1_000_000_000) : UInt64.max
    meta["key_deadline_uptime_ns"] = readyTicks > 0 ? Int(keyDeadlineNS) : 0
    meta["key_tail_s"] = keyTailS
    let stepNS = UInt64(1_000_000_000 / rateHz)
    let maxNS = UInt64((warmupS + measureS + 8) * 1_000_000_000)
    let poster = DispatchQueue(label: "sr0.poster", qos: .userInteractive)
    let src = CGEventSource(stateID: .privateState)
    var seq = 0
    var sent = 0
    var postFailures = 0
    let posterDone = Box(false)
    let stopBox = Box(false)
    poster.async {
        while !stopBox.value {
            let due = startNS + UInt64(seq) * stepNS
            if due - startNS > maxNS || !proc.isRunning || due >= keyDeadlineNS { break }
            while true {
                let now = MachClock.now()
                if now >= due { break }
                let rem = due - now
                if rem > 16_000_000 { usleep(8000) } else { for _ in 0..<64 { _ = 0 } }
            }
            let idx = seq % keyChars.count
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCodes[idx], keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: keyCodes[idx], keyDown: false) else { postFailures += 1; seq += 1; continue }
            let t = MachClock.now()
            tracker.willPost(seq: seq + 1, ch: keyChars[idx], tPost: t)
            down.postToPid(pid)
            up.postToPid(pid)
            sent += 1
            seq += 1
        }
        posterDone.value = true
    }
    // wait for the app to finish its self-timed run
    while proc.isRunning { try? await Task.sleep(nanoseconds: 500_000_000) }
    stopBox.value = true
    for _ in 0..<50 where !posterDone.value { try? await Task.sleep(nanoseconds: 100_000_000) }
    tracker.flushTimeouts()
    try? await stream.stopCapture()

    // 5) outputs
    let snap = tracker.snapshot
    var rows: [String] = []
    var okLat: [Double] = []
    for r in snap.resolved where r.seq >= 0 {
        let lat = r.status == "ok" ? Double(r.tDisplay &- r.tPost) / 1_000_000 : Double.nan
        if r.status == "ok" { okLat.append(lat) }
        rows.append("\(r.seq),\(r.ch),\(r.tPost),\(r.tDisplay),\(lat.isNaN ? "" : String(lat)),\(r.status),\(r.diffPx)")
    }
    writeText(outDir + "/keys.csv", "seq,char,t_post_ns,t_display_ns,latency_ms,status,diff_px\n" + rows.sorted().joined(separator: "\n") + "\n")
    writeText(outDir + "/frames_display.csv", "display_ns,region_hash\n" +
        zip(snap.frames, snap.hashes).map { "\($0),\(String($1, radix: 16))" }.joined(separator: "\n") + "\n")
    meta["keys_sent"] = sent
    meta["post_failures"] = postFailures
    meta["keys_resolved_ok"] = okLat.count
    meta["frames_captured"] = snap.frames.count
    meta["stream_errors"] = sink.errors
    meta["app_exit_status"] = Int(proc.terminationStatus)
    meta["region_selfcheck_ok"] = okLat.count >= Int(Double(max(1, sent)) * 0.9)
    writeText(outDir + "/recorder_meta.json", json(meta))
    print("RECORDER-DONE keys=\(sent) resolved=\(okLat.count) p95=\(percentile(okLat, 0.95)) ms frames=\(snap.frames.count)")
    return proc.terminationStatus == 0 ? 0 : 8
}

let delegateApp = NSApplication.shared
delegateApp.setActivationPolicy(.accessory)
Task { @MainActor in
    let code = await run()
    exit(code)
}
delegateApp.run()
