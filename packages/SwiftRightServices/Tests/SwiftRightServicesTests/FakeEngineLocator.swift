import Foundation

/// Finds the FakeEngine product built alongside the test bundle. Override with
/// SWIFTRIGHT_FAKE_ENGINE. Searches `.build/<triple>/debug` (and release) under the package root.
enum FakeEngineLocator {
    static var executableName: String {
        #if os(Windows)
        "FakeEngine.exe"
        #else
        "FakeEngine"
        #endif
    }

    static func url() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SWIFTRIGHT_FAKE_ENGINE"] {
            return URL(fileURLWithPath: override)
        }
        guard let root = packageRoot() else { throw FakeEngineError.notFound("Package.swift not found above #filePath") }
        let build = root.appendingPathComponent(".build")
        var candidates = [build.appendingPathComponent("debug"), build.appendingPathComponent("release")]
        if let entries = try? FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil) {
            candidates += entries.map { $0.appendingPathComponent("debug") }
        }
        for directory in candidates {
            let candidate = directory.appendingPathComponent(executableName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw FakeEngineError.notFound("no \(executableName) under \(build.path); run swift build first")
    }

    private static func packageRoot() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}

enum FakeEngineError: Error {
    case notFound(String)
}
