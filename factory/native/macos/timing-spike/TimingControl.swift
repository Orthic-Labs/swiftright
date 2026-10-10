import AppKit
import ApplicationServices
import CoreGraphics
import CoreMedia
import CoreVideo
import CryptoKit
import Darwin
import Foundation
@preconcurrency import ScreenCaptureKit

func timeRecord(_ time: CMTime) -> [String: Any] {
    ["value": time.value, "timescale": time.timescale, "flags": time.flags.rawValue, "epoch": time.epoch, "valid": time.isValid, "indefinite": time.isIndefinite]
}
func clocks() -> [String: Any] {
    let before = mach_absolute_time()
    let dispatch = DispatchTime.now().uptimeNanoseconds
    let host = CMClockGetTime(CMClockGetHostTimeClock())
    let after = mach_absolute_time()
    var scale = mach_timebase_info_data_t(); mach_timebase_info(&scale)
    return ["machBefore": before, "dispatchUptimeNs": dispatch, "cmHostTime": timeRecord(host), "cmHostSystemUnits": CMClockConvertHostTimeToSystemUnits(host), "machAfter": after, "machTimebase": ["numer": scale.numer, "denom": scale.denom]]
}
final class Log: @unchecked Sendable {
    let file: FileHandle
    let lock = NSLock()
    init(_ path: URL) throws {
        guard FileManager.default.createFile(atPath: path.path, contents: nil) else { throw NSError(domain: "Timing", code: 1) }
        file = try FileHandle(forWritingTo: path)
    }
    func record(_ item: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        var row = item; row["clocks"] = clocks()
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) { file.write(data); file.write(Data([10])) }
    }
}
final class Samples: NSObject, SCStreamOutput, @unchecked Sendable {
    let log: Log
    var number = 0
    init(_ log: Log) { self.log = log }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        number += 1
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let info = attachments?.first ?? [:]
        var row: [String: Any] = ["kind": "sample", "index": number, "callbackEntryClocks": clocks(), "sampleValid": sample.isValid, "presentationTime": timeRecord(CMSampleBufferGetPresentationTimeStamp(sample)), "duration": timeRecord(CMSampleBufferGetDuration(sample)), "decodeTime": timeRecord(CMSampleBufferGetDecodeTimeStamp(sample))]
        if let status = info[.status] as? NSNumber { row["frameStatusRaw"] = status }
        if let display = info[.displayTime] as? NSNumber { row["windowServerDisplayMachTime"] = display }
        if let scale = info[.scaleFactor] as? NSNumber { row["scaleFactor"] = scale }
        if let scale = info[.contentScale] as? NSNumber { row["contentScale"] = scale }
        if let clock = stream.synchronizationClock {
            row["streamClockAvailable"] = true
            row["streamClockNow"] = timeRecord(CMClockGetTime(clock))
            let converted = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sample), from: clock, to: CMClockGetHostTimeClock())
            row["presentationConvertedToHost"] = timeRecord(converted)
            if converted.isValid && !converted.isIndefinite { row["presentationHostSystemUnits"] = CMClockConvertHostTimeToSystemUnits(converted) }
        } else { row["streamClockAvailable"] = false }
        if let buffer = sample.imageBuffer {
            let lockStatus = CVPixelBufferLockBaseAddress(buffer, .readOnly)
            row["pixelLockStatus"] = lockStatus
            row["pixelBufferIsPlanar"] = CVPixelBufferIsPlanar(buffer)
            if lockStatus == kCVReturnSuccess { defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            if !CVPixelBufferIsPlanar(buffer), CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA, let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
                let data = Data(bytes: base, count: bytes)
                row["pixels"] = ["width": CVPixelBufferGetWidth(buffer), "height": CVPixelBufferGetHeight(buffer), "bytesPerRow": CVPixelBufferGetBytesPerRow(buffer), "pixelFormat": CVPixelBufferGetPixelFormatType(buffer), "bytes": bytes, "hashScope": "packed BGRA bytes including row padding; not GPU completion", "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
            } else { row["pixelHashStatus"] = "HELD: expected packed BGRA unavailable" }
            }
        }
        log.record(row)
    }
}
@MainActor final class BackgroundPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class MutationView: NSView {
    var sequence = 0
    var log: Log?
    override func draw(_ dirtyRect: NSRect) {
        log?.record(["kind": "appkit-draw-begin", "sequence": sequence])
        (sequence % 2 == 0 ? NSColor.red : NSColor.blue).setFill(); bounds.fill()
        NSColor.white.setFill(); NSRect(x: CGFloat(sequence % 20) * 6, y: 8, width: 5, height: 20).fill()
        log?.record(["kind": "appkit-draw-return", "sequence": sequence, "scope": "CPU AppKit draw return; not GPU completion"])
    }
}
func argument(_ key: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: key), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}
@main struct TimingControl {
    @MainActor static func main() throws {
        let permissions: [String: Any] = ["screenCaptureGranted": CGPreflightScreenCaptureAccess(), "axTrusted": AXIsProcessTrusted(), "permissionRequests": false]
        if CommandLine.arguments.contains("--preflight") {
            print(String(decoding: try JSONSerialization.data(withJSONObject: permissions, options: [.sortedKeys]), as: UTF8.self)); return
        }
        guard CommandLine.arguments.contains("--run"), permissions["screenCaptureGranted"] as? Bool == true else {
            print("HELD: no-prompt screen grant absent or explicit --run missing"); return
        }
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? ""
        guard executable.hasPrefix("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/timing-spike/"), let path = argument("--out") else { throw NSError(domain: "Timing", code: 2) }
        let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard root.path.hasPrefix("/Volumes/D/claude/swiftright/factory/native/macos/timing-spike/evidence/"), !FileManager.default.fileExists(atPath: root.appendingPathComponent("raw.jsonl").path) else { throw NSError(domain: "Timing", code: 3) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = try Log(root.appendingPathComponent("raw.jsonl"))
        log.record(["kind": "preflight", "permissions": permissions, "pid": getpid(), "executable": executable, "scope": "independent observational timing control; no case/tuple/parity evidence"])
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let window = BackgroundPanel(contentRect: NSRect(x: 24, y: 24, width: 192, height: 128), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        window.title = "FactoryTimingOwned-" + String(getpid())
        let view = MutationView(frame: NSRect(x: 0, y: 0, width: 192, height: 128)); view.log = log; window.contentView = view
        window.orderBack(nil); window.displayIfNeeded()
        log.record(["kind": "owned-window", "pid": getpid(), "windowID": window.windowNumber, "canBecomeKey": window.canBecomeKey, "canBecomeMain": window.canBecomeMain, "isKeyWindow": window.isKeyWindow, "appActive": app.isActive, "activationPolicy": "prohibited", "order": "back"])
        guard !window.isKeyWindow && !app.isActive else { window.close(); throw NSError(domain: "Timing", code: 5) }
        // Independent native watchdog; external launcher also owns a process-group deadline.
        DispatchQueue.global().asyncAfter(deadline: .now() + 12) { log.record(["kind": "watchdog-timeout"]); exit(3) }
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) && $0.owningApplication?.processID == getpid() }) else { throw NSError(domain: "Timing", code: 4) }
                let configuration = SCStreamConfiguration()
                configuration.width = 192; configuration.height = 128
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                configuration.queueDepth = 5; configuration.showsCursor = false
                configuration.capturesAudio = false; configuration.captureMicrophone = false
                configuration.presenterOverlayPrivacyAlertSetting = .never
                let samples = Samples(log), queue = DispatchQueue(label: "FactoryTiming.samples")
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration, delegate: nil)
                try stream.addStreamOutput(samples, type: .screen, sampleHandlerQueue: queue)
                log.record(["kind": "capture-start-submit", "ownedFilterPID": own.owningApplication!.processID, "ownedFilterWindowID": own.windowID, "configuration": ["width": 192, "height": 128, "pixelFormat": "BGRA", "frameInterval": "1/60", "queueDepth": 5, "audio": false, "microphone": false, "cursor": false]])
                try await stream.startCapture(); log.record(["kind": "capture-start-completed"])
                let producer = DispatchSource.makeTimerSource(queue: .main)
                producer.schedule(deadline: .now(), repeating: .milliseconds(100))
                producer.setEventHandler {
                    view.sequence += 1; log.record(["kind": "content-mutation-submit", "sequence": view.sequence]); view.needsDisplay = true; view.displayIfNeeded()
                }
                producer.resume()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    log.record(["kind": "producer-stall-begin", "intentionalDurationNs": 350_000_000])
                    Thread.sleep(forTimeInterval: 0.35)
                    log.record(["kind": "producer-stall-end"])
                }
                try await Task.sleep(for: .seconds(5))
                producer.cancel(); log.record(["kind": "capture-stop-submit"])
                try await stream.stopCapture(); queue.sync {}
                log.record(["kind": "capture-stop-completed", "samples": samples.number])
            } catch { log.record(["kind": "native-error", "message": String(describing: error)]) }
            window.close(); log.record(["kind": "owned-window-closed"]); app.terminate(nil)
        }
        app.run()
    }
}
