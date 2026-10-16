import Foundation
import SwiftRightHost
import PulseHub
import RightKitHub
import RightKitHubQA

/// The probe's platform services: Pulse's `RecordingPlatformServices` for every member except image decoding.
/// Pulse's recording services answer `decodeImage` with nil off macOS, so every app icon fell back to the glyph.
/// This wrapper answers it with SwiftRightHost's `ImageDecoder`, the same decoder the protocol default uses on Windows.
/// Temporary round-8 log: one `PROBE_DECODE` line per call (ok with size, or fail with the error).
struct ProbeHubServices: HubPlatformServices, @unchecked Sendable {
    let base = RecordingPlatformServices()

    func revealFile(_ path: String) async throws { try await base.revealFile(path) }
    func openURL(_ url: URL) async throws { try await base.openURL(url) }
    func moveToTrash(_ path: String) async throws { try await base.moveToTrash(path) }
    func permissionStatus(_ id: String) async -> HubPermissionStatus { await base.permissionStatus(id) }
    func requestPermission(_ id: String) async throws -> HubPermissionStatus { try await base.requestPermission(id) }
    func readClipboardText() async throws -> String? { try await base.readClipboardText() }
    func writeClipboardText(_ text: String) async throws { try await base.writeClipboardText(text) }
    func postNotification(_ notification: HubNotification) async throws { try await base.postNotification(notification) }
    func setTrayPresence(_ presence: HubTrayPresence?) async throws { try await base.setTrayPresence(presence) }
    var trayActivations: AsyncStream<Void> { base.trayActivations }
    func isLaunchAtLoginEnabled() async throws -> Bool { try await base.isLaunchAtLoginEnabled() }
    func setLaunchAtLogin(_ enabled: Bool) async throws { try await base.setLaunchAtLogin(enabled) }
    func claimSingleInstance(_ id: String) async throws -> Bool { try await base.claimSingleInstance(id) }
    func chooseFolder(prompt: String, startingAt: String?) async throws -> String? {
        try await base.chooseFolder(prompt: prompt, startingAt: startingAt)
    }
    func registerFont(_ data: Data) throws -> String { try base.registerFont(data) }

    func decodeImage(_ data: Data, maxPixel: Int) async -> HubImage? {
        do {
            let image = try ImageDecoder.decode(data, maxPixel: maxPixel)
            print("PROBE_DECODE ok \(image.width)x\(image.height) from \(data.count) bytes max \(maxPixel)"); fflush(stdout)
            return HubImage(rgba: image)
        } catch {
            print("PROBE_DECODE fail \(data.count) bytes: \(error)"); fflush(stdout)
            return nil
        }
    }
}
