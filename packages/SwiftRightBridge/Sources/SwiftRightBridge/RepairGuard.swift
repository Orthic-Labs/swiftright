import Foundation
#if os(Windows)
import WinSDK
#endif

/// W08 Tier 2: out-of-package repair guard for MSIX apps.
///
/// An MSIX update cancelled while Windows registers it can leave the old package `Modified, NeedsRemediation`, which cannot be
/// launched, so nothing inside the package can repair it. On every normal launch `Bridge.run` calls `installIfNeeded`, which
/// (packaged Windows runs only) writes the guard script (`repair-guard.ps1`) to `%LOCALAPPDATA%\<AppName>\repair\` and has it register the
/// per-user scheduled task `<PFN>-Repair` (event 751 in the AppX deployment log, and logon). The task re-adds the package from
/// its App Installer feed, logs every decision, and removes itself when the app is uninstalled.
///
/// Steady state is one small file read, plus one hidden `schtasks /query` off the main thread to prove the task still exists;
/// nothing is installed while the script on disk equals the embedded one, `guard.json` names this package family and the task
/// exists. If the installer fails (task registration refused, validation failed) the attempt marker `install-attempt.json` stays
/// and no new installer is spawned for 24 hours unless the embedded script changes (so a broken machine is not re-spawning hidden
/// PowerShell and refetching the feed on every launch). Opt out with SWIFTRIGHT_REPAIR_GUARD=0. Requires a physical
/// `%LOCALAPPDATA%` (MSIX file system write virtualization disabled), as the data contract of an app that keeps user data outside the
/// package already does.
///
/// Ownership: the script is the RightKit canonical `packages/release/msix-repair-guard.ps1`; SwiftRightBridge embeds a byte copy
/// pinned by `guard/rightkit-pin.json` (see `tools/gen-repair-guard.mjs`).
public enum RepairGuard {
    /// How long a failed installer attempt suppresses new attempts (unless the embedded script changed).
    static let attemptBackoff: TimeInterval = 24 * 3600

    /// Pure decision, testable on any platform: does the guard need (re)installing? `taskExists` is evaluated last and only when
    /// the cheap file checks pass.
    static func needsInstall(scriptOnDisk: String?, configJSON: Data?, pfn: String, taskExists: () -> Bool = { true }) -> Bool {
        guard scriptOnDisk == RepairGuardScript.source else { return true }
        guard let data = configJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["pfn"] as? String) == pfn,
              let task = object["task"] as? String, !task.isEmpty else { return true }
        return !taskExists()
    }

    /// Pure: is a new installer attempt suppressed by a previous failed attempt (marker still on disk after the installer ran)?
    static func installAttemptBlocked(markerJSON: Data?, now: Date, scriptSha256: String = RepairGuardScript.sha256) -> Bool {
        guard let data = markerJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["sha256"] as? String) == scriptSha256,
              let epoch = (object["epoch"] as? NSNumber)?.doubleValue else { return false }
        let age = now.timeIntervalSince1970 - epoch
        return age >= 0 && age < attemptBackoff
    }

    static func attemptMarker(now: Date, scriptSha256: String = RepairGuardScript.sha256) -> Data {
        Data("{\"epoch\":\(Int(now.timeIntervalSince1970)),\"sha256\":\"\(scriptSha256)\"}".utf8)
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
            let marker = dir.appendingPathComponent("install-attempt.json")
            let systemRoot = env["SystemRoot"] ?? "C:\\Windows"
            let onDisk = (try? Data(contentsOf: script)).flatMap { String(data: $0, encoding: .utf8) }
            guard needsInstall(scriptOnDisk: onDisk, configJSON: try? Data(contentsOf: config), pfn: pfn,
                               taskExists: { taskExists(name: pfn + "-Repair", systemRoot: systemRoot) }) else { return }
            if installAttemptBlocked(markerJSON: try? Data(contentsOf: marker), now: Date()) {
                appendLog(dir: dir, "install skipped: the previous installer attempt did not finish successfully less than 24 h ago (install-attempt.json); retried after that or when the embedded script changes")
                return
            }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data(RepairGuardScript.source.utf8).write(to: script, options: .atomic)
                try attemptMarker(now: Date()).write(to: marker, options: .atomic)
            } catch { return }
            appendLog(dir: dir, "installer started (script changed, guard.json missing or task missing)")
            launchHidden(script: script.path.replacingOccurrences(of: "/", with: "\\"), pfn: pfn, systemRoot: systemRoot)
        }
        #endif
    }

    #if os(Windows)
    /// Appends one line to repair.log (the script's own log), tagged `[app]`.
    static func appendLog(dir: URL, _ message: String) {
        let url = dir.appendingPathComponent("repair.log")
        let formatter = ISO8601DateFormatter()
        guard let data = (formatter.string(from: Date()) + " [app] " + message + "\r\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    /// CreateProcessW + CREATE_NO_WINDOW (no visible console, no inherited handles). Foundation's `Process` is not used: with
    /// FileHandle.nullDevice on stdio it fast-fails (0xc0000409) inside a packaged launch. Returns the process handle, or nil.
    static func createHidden(_ line: String) -> PROCESS_INFORMATION? {
        var commandLine = Array(line.utf16)
        commandLine.append(0)
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        startup.dwFlags = DWORD(STARTF_USESHOWWINDOW)
        startup.wShowWindow = WORD(SW_HIDE)
        var info = PROCESS_INFORMATION()
        let started = commandLine.withUnsafeMutableBufferPointer { buffer in
            CreateProcessW(nil, buffer.baseAddress, nil, nil, false, DWORD(CREATE_NO_WINDOW), nil, nil, &startup, &info)
        }
        return started ? info : nil
    }

    /// Runs the guard installer detached and hidden.
    static func launchHidden(script: String, pfn: String, systemRoot: String) {
        let exe = systemRoot + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
        guard let info = createHidden("\"" + exe + "\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script
            + "\" -Install -Pfn \"" + pfn + "\"") else { return }
        CloseHandle(info.hThread)
        CloseHandle(info.hProcess)
    }

    /// `schtasks /query /tn <name>` (hidden, waits up to 10 s): true when the task exists. Any doubt (cannot spawn, timeout) counts
    /// as "exists": a failed probe must not turn into an install on every launch.
    static func taskExists(name: String, systemRoot: String) -> Bool {
        let exe = systemRoot + "\\System32\\schtasks.exe"
        guard let info = createHidden("\"" + exe + "\" /query /tn \"" + name + "\"") else { return true }
        defer { CloseHandle(info.hThread); CloseHandle(info.hProcess) }
        guard WaitForSingleObject(info.hProcess, 10_000) == 0 else { return true }
        var code: DWORD = 1
        guard GetExitCodeProcess(info.hProcess, &code) else { return true }
        return code == 0
    }

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
