import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

enum ObservationStatus: String, Encodable {
    case observed = "OBSERVED"
    case blocked = "BLOCKED"
    case unobserved = "UNOBSERVED"
    case notAttempted = "NOT_ATTEMPTED"
}

struct Observation: Encodable {
    let status: ObservationStatus
    let detail: String
    let values: [String: String]

    init(_ status: ObservationStatus, _ detail: String, _ values: [String: String] = [:]) {
        self.status = status
        self.detail = detail
        self.values = values
    }
}

struct Result: Encodable {
    let schemaVersion = 1
    let mode: String
    let overallStatus: String
    let captureGuard: Observation
    let observations: [String: Observation]
}

final class Recorder: @unchecked Sendable {
    var textLines = 0
    var textRuns = 0
    var firstRunValues: [String: String] = [:]
    var layoutEvents: [String] = []
    var placements = 0
}

let recorder = Recorder()

struct RunRecorder: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            recorder.textLines += 1
            for run in line {
                recorder.textRuns += 1
                if recorder.firstRunValues.isEmpty {
                    let bounds = run.typographicBounds
                    recorder.firstRunValues = [
                        "ascent": String(describing: bounds.ascent),
                        "descent": String(describing: bounds.descent),
                        "leading": String(describing: bounds.leading),
                        "width": String(describing: bounds.width)
                    ]
                }
                context.draw(run)
            }
        }
    }
}

struct ProposalRecorderLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let child = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        let proposedWidth = proposal.width.map { String(describing: $0) } ?? "nil"
        let proposedHeight = proposal.height.map { String(describing: $0) } ?? "nil"
        recorder.layoutEvents.append("proposal=\(proposedWidth)x\(proposedHeight);child=\(child.width)x\(child.height)")
        return CGSize(width: proposal.width ?? child.width, height: proposal.height ?? child.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            recorder.placements += 1
        }
    }
}

@MainActor
func structuralProbe() -> [String: Observation] {
    recorder.textLines = 0
    recorder.textRuns = 0
    recorder.firstRunValues = [:]
    recorder.layoutEvents = []
    recorder.placements = 0

    let view = ProposalRecorderLayout {
        Text("SwiftRight capture probe")
            .font(.system(size: 17))
            .textRenderer(RunRecorder())
    }
    .frame(width: 280, height: 72)
    let image = ImageRenderer(content: view)
    image.scale = 1
    let cgImage = image.cgImage

    var text: Observation
    if !recorder.firstRunValues.isEmpty, recorder.textLines > 0, recorder.textRuns > 0 {
        text = Observation(.observed, "TextRenderer draw callback observed through ImageRenderer.", [
            "lines": String(recorder.textLines),
            "runs": String(recorder.textRuns),
            "ascent": recorder.firstRunValues["ascent"]!,
            "descent": recorder.firstRunValues["descent"]!,
            "leading": recorder.firstRunValues["leading"]!,
            "width": recorder.firstRunValues["width"]!
        ])
    } else {
        text = Observation(.unobserved, "TextRenderer compiled but its draw callback did not run in offscreen render.")
    }

    let layout: Observation
    if !recorder.layoutEvents.isEmpty && recorder.placements > 0 {
        layout = Observation(.observed, "Custom Layout received proposal & placement callbacks through ImageRenderer.", [
            "events": String(recorder.layoutEvents.count),
            "placements": String(recorder.placements),
            "firstEvent": recorder.layoutEvents[0]
        ])
    } else {
        layout = Observation(.unobserved, "Layout compiled but its proposal or placement callback did not run.")
    }

    if let cgImage {
        return [
            "textRenderer": text,
            "layout": layout,
            "offscreenImage": Observation(.observed, "ImageRenderer produced a non-windowed CGImage.", [
                "width": String(cgImage.width), "height": String(cgImage.height)
            ]),
            "screenCaptureKit": Observation(.notAttempted, "Requires --vm-capture plus VM guard."),
            "externalAX": Observation(.notAttempted, "Requires --vm-capture plus VM guard.")
        ]
    }
    return [
        "textRenderer": text,
        "layout": layout,
        "offscreenImage": Observation(.unobserved, "ImageRenderer did not produce a CGImage."),
        "screenCaptureKit": Observation(.notAttempted, "Requires --vm-capture plus VM guard."),
        "externalAX": Observation(.notAttempted, "Requires --vm-capture plus VM guard.")
    ]
}

@MainActor
func virtualMachineGuard() -> Observation {
    var hypervisor: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let hypervisorResult = sysctlbyname("kern.hv_vmm_present", &hypervisor, &size, nil, 0)
    var modelBuffer = [CChar](repeating: 0, count: 256)
    size = modelBuffer.count
    let modelResult = sysctlbyname("hw.model", &modelBuffer, &size, nil, 0)
    let model = String(decoding: modelBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    guard hypervisorResult == 0, hypervisor == 1, modelResult == 0, model.hasPrefix("VirtualMac") else {
        return Observation(.blocked, "VM capture requires kern.hv_vmm_present=1 & hw.model beginning VirtualMac.", [
            "hv": hypervisorResult == 0 ? String(hypervisor) : "sysctl-error-\(hypervisorResult)",
            "model": modelResult == 0 ? model : "sysctl-error-\(modelResult)"
        ])
    }
    return Observation(.observed, "Hypervisor & VirtualMac guard accepted.", ["hv": String(hypervisor), "model": model])
}

func externalAXSnapshot(processID: pid_t) -> Observation {
    let path = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("mac-capture-ax-client").path
    guard FileManager.default.isExecutableFile(atPath: path) else {
        return Observation(.blocked, "Cross-process AX client was not beside mac-capture-spike.", ["path": path])
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--pid", String(processID)]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return Observation(.blocked, "Cross-process AX client exceeded four-second bound.")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "OBSERVED" else {
            return Observation(.blocked, "Cross-process AX client did not observe a target control.", ["exit": String(process.terminationStatus), "output": String(decoding: data, as: UTF8.self)])
        }
        return Observation(.observed, json["detail"] as? String ?? "Separate AX client observed target control.")
    } catch {
        return Observation(.blocked, "Cross-process AX client could not start.", ["error": String(describing: error)])
    }
}

@MainActor
func vmCaptureProbe() async -> [String: Observation] {
    let processID = ProcessInfo.processInfo.processIdentifier
    let title = "SwiftRightCaptureSpike-\(processID)"
    let button = NSButton(title: "Probe control", target: nil, action: nil)
    let window = NSWindow(
        contentRect: NSRect(x: 80, y: 80, width: 360, height: 220),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = title
    window.contentView = button
    window.makeKeyAndOrderFront(nil)

    let popover = NSPopover()
    popover.behavior = .applicationDefined
    popover.contentSize = NSSize(width: 180, height: 72)
    popover.contentViewController = NSViewController()
    popover.contentViewController?.view = NSTextField(labelWithString: "Capture popover")
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    defer {
        popover.performClose(nil)
        window.orderOut(nil)
        window.close()
    }

    try? await Task.sleep(for: .milliseconds(400))
    let ax = await Task.detached { externalAXSnapshot(processID: processID) }.value
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == processID }
        guard let display = content.displays.first, !ownWindows.isEmpty else {
            return [
                "screenCaptureKit": Observation(.unobserved, "ScreenCaptureKit found no own composited window or display.", ["ownWindows": String(ownWindows.count)]),
                "popover": Observation(popover.isShown ? .observed : .unobserved, "Popover presentation state; capture-image pixels are not classified.", ["shown": String(popover.isShown)]),
                "externalAX": ax
            ]
        }
        let filter = SCContentFilter(display: display, including: ownWindows)
        let config = SCStreamConfiguration()
        config.width = 640
        config.height = 480
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return [
            "screenCaptureKit": Observation(.observed, "ScreenCaptureKit returned a compositor image for own window set.", [
                "windowCount": String(ownWindows.count),
                "imageWidth": String(image.width),
                "imageHeight": String(image.height)
            ]),
            "popover": Observation(popover.isShown ? .observed : .unobserved, "Popover presentation state; capture-image pixels are not classified.", ["shown": String(popover.isShown)]),
            "externalAX": ax
        ]
    } catch {
        return [
            "screenCaptureKit": Observation(.blocked, "ScreenCaptureKit capture failed; no capture success is claimed.", ["error": String(describing: error)]),
            "popover": Observation(popover.isShown ? .observed : .unobserved, "Popover presentation state; capture-image pixels are not classified.", ["shown": String(popover.isShown)]),
            "externalAX": ax
        ]
    }
}

@main
struct MacCaptureSpike {
    @MainActor
    static func main() async {
        let args = Set(CommandLine.arguments.dropFirst())
        let vmMode = args.contains("--vm-capture")
        let guardResult = virtualMachineGuard()
        var observations = structuralProbe()
        if vmMode {
            if guardResult.status == .observed {
                observations.merge(await vmCaptureProbe(), uniquingKeysWith: { _, new in new })
            } else {
                observations["screenCaptureKit"] = Observation(.blocked, "VM capture was requested but guard rejected execution.")
                observations["externalAX"] = Observation(.blocked, "VM capture was requested but guard rejected execution.")
            }
        }
        let passed = observations.values.allSatisfy { $0.status != .unobserved }
        let result = Result(
            mode: vmMode ? "vm-capture" : "structural",
            overallStatus: passed ? "COMPLETE_WITH_LIMITS" : "INCOMPLETE",
            captureGuard: guardResult,
            observations: observations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result), let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }
}
