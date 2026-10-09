import Foundation

/// One running engine process and its pipes. Reference type so actor-owned state can hold it.
final class EngineSession: @unchecked Sendable {
    let generation: UInt64
    let process: Process
    /// Parent's write end of the engine's stdin.
    let stdin: FileHandle
    /// Serial queue so frames reach stdin in the order they were enqueued, off the actor.
    let queue: DispatchQueue
    let exit: EngineExitBox

    init(generation: UInt64, process: Process, stdin: FileHandle, queue: DispatchQueue, exit: EngineExitBox) {
        self.generation = generation
        self.process = process
        self.stdin = stdin
        self.queue = queue
        self.exit = exit
    }
}

/// Records the engine's exit status once its stdout reaches end of file.
final class EngineExitBox: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var recorded: Int32?

    init(process: Process) {
        self.process = process
    }

    /// Blocks on the reader thread until the process exits, then records its status.
    func waitAndRecord() {
        process.waitUntilExit()
        let code = process.terminationStatus
        lock.lock()
        recorded = code
        lock.unlock()
    }

    var status: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

/// Carries a non-Sendable FileHandle into the reader thread. Only that thread reads it.
final class UncheckedHandle: @unchecked Sendable {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
}

enum EnginePipes {
    /// Reads a pipe on a dedicated thread (blocking reads cannot run on the actor or the
    /// cooperative pool). The stream finishes at end of file; `onEnd` runs first.
    static func pump(_ handle: FileHandle, into continuation: AsyncStream<Data>.Continuation,
                     onEnd: (@Sendable () -> Void)?) {
        let box = UncheckedHandle(handle)
        let thread = Thread {
            // availableData returns as soon as bytes arrive. read(upToCount:) waits for the full count or EOF.
            while case let data = box.handle.availableData, !data.isEmpty {
                continuation.yield(data)
            }
            onEnd?()
            continuation.finish()
        }
        thread.start()
    }
}
