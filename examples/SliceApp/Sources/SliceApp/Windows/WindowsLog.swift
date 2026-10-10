#if os(Windows)
import Foundation
import WinSDK

// SliceApp.exe is a GUI-subsystem executable (linked /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup by
// scripts/build-windows.ps1), so a packaged launch opens no console window. It also has no standard handles
// unless the parent supplies them: `print` would go nowhere, and the SWR_STARTUP_ERROR / SLICE_*_ERROR
// diagnostics that the QA driver and the clean-machine harness read would be lost.
//
// Contract:
//   - stdout or stderr backed by a usable handle (a pipe, a file, `> out.txt`, an attached console): unchanged.
//     The QA driver redirects both to pipes and reads the diagnostics from them.
//   - stdout or stderr without a usable handle (a packaged launch from the Start menu or AUMID activation): the
//     C stream and the process standard handle are pointed at an append-only, unbuffered log file,
//     %LOCALAPPDATA%\SliceApp\slice-app.log (else %TEMP%\slice-app.log). The file is rewritten when it exceeds
//     256 KiB. A first line names the launch (time, pid, exe) so the log proves the redirect.
// Nothing here can fail the launch: any error leaves the streams as they were.

private let logLimitBytes: UInt64 = 256 * 1024

private func isUsableStdHandle(_ kind: Int32) -> Bool {
    guard let handle = GetStdHandle(DWORD(bitPattern: kind)), handle != INVALID_HANDLE_VALUE else { return false }
    return GetFileType(handle) != 0  // 0 = FILE_TYPE_UNKNOWN (closed or invalid handle)
}

private func logFileURL() -> URL? {
    let env = ProcessInfo.processInfo.environment
    if let base = env["LOCALAPPDATA"], !base.isEmpty {
        return URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent(SliceAppData.directoryName, isDirectory: true)
            .appendingPathComponent("slice-app.log", isDirectory: false)
    }
    if let temp = env["TEMP"], !temp.isEmpty {
        return URL(fileURLWithPath: temp, isDirectory: true).appendingPathComponent("slice-app.log", isDirectory: false)
    }
    return nil
}

/// Re-opens `stream` onto the log. `mode` is "a" (append) or "w" (rewrite).
private func reopen(_ stream: UnsafeMutablePointer<FILE>, path: String, mode: String) -> Bool {
    var reopened: UnsafeMutablePointer<FILE>?
    let status: errno_t = path.withCString(encodedAs: UTF16.self) { widePath in
        mode.withCString(encodedAs: UTF16.self) { wideMode in _wfreopen_s(&reopened, widePath, wideMode, stream) }
    }
    guard status == 0, reopened != nil else { return false }
    setvbuf(stream, nil, _IONBF, 0)
    return true
}

/// Call first thing in `main`, before anything prints.
func sliceAppRedirectStdioIfDetached() {
    let outDetached = !isUsableStdHandle(-11)  // STD_OUTPUT_HANDLE
    let errDetached = !isUsableStdHandle(-12)  // STD_ERROR_HANDLE
    guard outDetached || errDetached, let url = logFileURL() else { return }

    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    let mode = size > logLimitBytes ? "w" : "a"

    var outRedirected = false
    var redirected = false
    if outDetached, reopen(stdout, path: url.path, mode: mode) {
        outRedirected = true
        redirected = true
        // Keep the process standard handle in step so child processes and FileHandle.standardOutput agree.
        let os = _get_osfhandle(_fileno(stdout))
        if os != -1 { _ = SetStdHandle(DWORD(bitPattern: -11), HANDLE(bitPattern: os)) }
    }
    if errDetached, reopen(stderr, path: url.path, mode: redirected && mode == "w" ? "a" : mode) {
        redirected = true
        let os = _get_osfhandle(_fileno(stderr))
        if os != -1 { _ = SetStdHandle(DWORD(bitPattern: -12), HANDLE(bitPattern: os)) }
    }
    if redirected {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let exe = ProcessInfo.processInfo.arguments.first ?? "SliceApp.exe"
        fputs("slice-app: log opened \(stamp) pid=\(GetCurrentProcessId()) exe=\(exe)\n", outRedirected ? stdout : stderr)
    }
}
#endif
