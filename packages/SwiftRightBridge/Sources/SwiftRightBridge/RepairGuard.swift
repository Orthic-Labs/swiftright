import Foundation
#if os(Windows)
import WinSDK
#endif

/// W08 Tier 2: out-of-package repair guard for MSIX apps.
///
/// An MSIX update cancelled while Windows registers it can leave the old package `Modified, NeedsRemediation`, which cannot be
/// launched, so nothing inside the package can repair it. On every normal launch `Bridge.run` calls `installIfNeeded`, which
/// (packaged Windows runs only) writes `guard/repair-guard.ps1` to `%LOCALAPPDATA%\<AppName>\repair\` and has it register the
/// per-user scheduled task `<PFN>-Repair` (event 751 in the AppX deployment log, and logon). The task re-adds the package from
/// its App Installer feed, logs every decision, and removes itself when the app is uninstalled.
///
/// Steady state is one small file read: nothing is spawned while the script on disk equals the embedded one and `guard.json`
/// names this package family. Opt out with SWIFTRIGHT_REPAIR_GUARD=0. Requires a physical `%LOCALAPPDATA%` (MSIX file system
/// write virtualization disabled), as the data contract of an app that keeps user data outside the package already does.
public enum RepairGuard {
    /// Pure decision, testable on any platform: does the guard need (re)installing?
    static func needsInstall(scriptOnDisk: String?, configJSON: Data?, pfn: String) -> Bool {
        guard scriptOnDisk == RepairGuardScript.source else { return true }
        guard let data = configJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["pfn"] as? String) == pfn,
              let task = object["task"] as? String, !task.isEmpty else { return true }
        return false
    }

    /// Folder-name-safe form of an app name.
    static func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return cleaned.isEmpty ? "App" : cleaned
    }

    /// Never blocks the caller beyond a small file read; the install runs detached and hidden.
    public static func installIfNeeded(appName: String) {
        #if os(Windows)
        let env = ProcessInfo.processInfo.environment
        if env["SWIFTRIGHT_REPAIR_GUARD"] == "0" { return }
        guard let pfn = currentPackageFamilyName() else { return }   // unpackaged: nothing to guard
        guard let base = env["LOCALAPPDATA"], !base.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let dir = URL(fileURLWithPath: base, isDirectory: true)
                .appendingPathComponent(sanitized(appName), isDirectory: true)
                .appendingPathComponent("repair", isDirectory: true)
            let script = dir.appendingPathComponent("repair-guard.ps1")
            let config = dir.appendingPathComponent("guard.json")
            let onDisk = (try? Data(contentsOf: script)).flatMap { String(data: $0, encoding: .utf8) }
            guard needsInstall(scriptOnDisk: onDisk, configJSON: try? Data(contentsOf: config), pfn: pfn) else { return }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data(RepairGuardScript.source.utf8).write(to: script, options: .atomic)
            } catch { return }
            // conhost --headless: PowerShell without a visible console window.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: (env["SystemRoot"] ?? "C:\\Windows") + "\\System32\\conhost.exe")
            p.arguments = ["--headless", "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                           "-WindowStyle", "Hidden", "-File", script.path.replacingOccurrences(of: "/", with: "\\"),
                           "-Install", "-Pfn", pfn]
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
        #endif
    }

    #if os(Windows)
    static func currentPackageFamilyName() -> String? {
        var length: UInt32 = 0
        let probe = GetCurrentPackageFamilyName(&length, nil)
        guard probe == 122, length > 1 else { return nil }   // ERROR_INSUFFICIENT_BUFFER; 15700 = no package identity
        var buffer = [UInt16](repeating: 0, count: Int(length))
        guard GetCurrentPackageFamilyName(&length, &buffer) == 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length) - 1), as: UTF16.self)
    }
    #endif
}
