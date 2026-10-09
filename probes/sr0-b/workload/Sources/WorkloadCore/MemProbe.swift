import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#endif

// R10 memory diagnosis: in-process memory accounting for the headless soak (`WorkloadWin --soak`). Nothing here runs in a timed
// workload run. Windows: the process heaps (`HeapSummary` per heap: allocated and committed bytes, the numbers the renderer's
// memory sampler reported) plus the commit charge (`PrivateUsage`, what the harness calls private bytes). macOS: the malloc zones
// (`malloc_zone_statistics`) plus `phys_footprint`.

public struct MemSample: Sendable {
    /// Windows: PrivateUsage (commit charge). macOS: phys_footprint.
    public var privateBytes: UInt64 = 0
    /// Bytes handed out by the allocator and still live (Windows: sum of `HeapSummary.cbAllocated`; macOS: malloc `size_in_use`).
    public var heapAllocated: UInt64 = 0
    /// Bytes the allocator holds from the OS (Windows: `cbCommitted`; macOS: malloc `size_allocated`).
    public var heapCommitted: UInt64 = 0
    /// Live blocks (macOS only; 0 on Windows, where the census below counts them).
    public var blocks: UInt64 = 0
    public var heaps = 0
    public init() {}
}

public enum MemProbe {
    #if os(Windows)
    /// The commit charge (PrivateUsage), cheap enough to read once a second inside a timed run (no heap walk).
    public static func privateBytes() -> UInt64 {
        var counters = PROCESS_MEMORY_COUNTERS_EX()
        counters.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS_EX>.size)
        let ok = withUnsafeMutablePointer(to: &counters) { pointer in
            pointer.withMemoryRebound(to: PROCESS_MEMORY_COUNTERS.self, capacity: 1) {
                K32GetProcessMemoryInfo(GetCurrentProcess(), $0, DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS_EX>.size))
            }
        }
        return ok ? UInt64(counters.PrivateUsage) : 0
    }

    public static func sample() -> MemSample {
        var s = MemSample()
        var counters = PROCESS_MEMORY_COUNTERS_EX()
        counters.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS_EX>.size)
        let ok = withUnsafeMutablePointer(to: &counters) { pointer in
            pointer.withMemoryRebound(to: PROCESS_MEMORY_COUNTERS.self, capacity: 1) {
                K32GetProcessMemoryInfo(GetCurrentProcess(), $0, DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS_EX>.size))
            }
        }
        if ok { s.privateBytes = UInt64(counters.PrivateUsage) }
        var handles = [HANDLE?](repeating: nil, count: 128)
        let count = Int(GetProcessHeaps(DWORD(handles.count), &handles))
        s.heaps = count
        for index in 0..<min(count, handles.count) {
            guard let heap = handles[index] else { continue }
            var summary = HEAP_SUMMARY()
            summary.cb = DWORD(MemoryLayout<HEAP_SUMMARY>.size)
            if HeapSummary(heap, 0, &summary) {
                s.heapAllocated += UInt64(summary.cbAllocated)
                s.heapCommitted += UInt64(summary.cbCommitted)
            }
        }
        return s
    }
    #elseif canImport(Darwin)
    public static func privateBytes() -> UInt64 { sample().privateBytes }

    public static func sample() -> MemSample {
        var s = MemSample()
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        s.heapAllocated = UInt64(stats.size_in_use)
        s.heapCommitted = UInt64(stats.size_allocated)
        s.blocks = UInt64(stats.blocks_in_use)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if rc == KERN_SUCCESS { s.privateBytes = UInt64(info.phys_footprint) }
        s.heaps = 1
        return s
    }
    #else
    public static func privateBytes() -> UInt64 { 0 }
    public static func sample() -> MemSample { MemSample() }
    #endif
}

/// Busy-block census of the process heaps by size class (Windows: `HeapWalk`), for a before/after diff. A size class is a power of two:
/// `class k` holds blocks of 2^(k-1) < size <= 2^k bytes. The walk allocates nothing (the heap is locked while it runs).
public struct HeapCensus: Sendable {
    public static let classes = 40
    public var busyCount = [UInt64](repeating: 0, count: HeapCensus.classes)
    public var busyBytes = [UInt64](repeating: 0, count: HeapCensus.classes)
    public var freeBytes: UInt64 = 0
    public var regionBytes: UInt64 = 0
    public var walked = false
    public init() {}

    #if os(Windows)
    public static func take() -> HeapCensus {
        var census = HeapCensus()
        // Everything the walk touches is allocated before the first HeapLock: an allocation from a locked heap by this thread is fine
        // (the lock is recursive for its owner) but a counter array that grows is not wanted, so the arrays are used in place.
        var handles = [HANDLE?](repeating: nil, count: 128)
        let count = min(Int(GetProcessHeaps(DWORD(handles.count), &handles)), handles.count)
        let busy = UnsafeMutablePointer<UInt64>.allocate(capacity: classes)
        let bytes = UnsafeMutablePointer<UInt64>.allocate(capacity: classes)
        busy.initialize(repeating: 0, count: classes)
        bytes.initialize(repeating: 0, count: classes)
        var free: UInt64 = 0
        var region: UInt64 = 0
        for index in 0..<count {
            guard let heap = handles[index] else { continue }
            guard HeapLock(heap) else { continue }
            var entry = PROCESS_HEAP_ENTRY()
            entry.lpData = nil
            while HeapWalk(heap, &entry) {
                let flags = Int32(entry.wFlags)
                if flags & Int32(PROCESS_HEAP_ENTRY_BUSY) != 0 {
                    let size = UInt64(entry.cbData)
                    var k = 0
                    while k < classes - 1, (UInt64(1) << UInt64(k)) < size { k += 1 }
                    busy[k] += 1
                    bytes[k] += size
                } else if flags & Int32(PROCESS_HEAP_REGION) != 0 {
                    region += UInt64(entry.cbData)
                } else if flags & Int32(PROCESS_HEAP_UNCOMMITTED_RANGE) == 0 {
                    free += UInt64(entry.cbData)
                }
            }
            HeapUnlock(heap)
        }
        for k in 0..<classes { census.busyCount[k] = busy[k]; census.busyBytes[k] = bytes[k] }
        busy.deallocate()
        bytes.deallocate()
        census.freeBytes = free
        census.regionBytes = region
        census.walked = true
        return census
    }
    #else
    public static func take() -> HeapCensus { HeapCensus() }
    #endif

    /// Rows (class, count delta, bytes delta) sorted by byte growth, largest first.
    public func growth(since earlier: HeapCensus) -> [(sizeClass: Int, count: Int64, bytes: Int64)] {
        var rows: [(sizeClass: Int, count: Int64, bytes: Int64)] = []
        for k in 0..<HeapCensus.classes {
            let c = Int64(busyCount[k]) - Int64(earlier.busyCount[k])
            let b = Int64(busyBytes[k]) - Int64(earlier.busyBytes[k])
            if c != 0 || b != 0 { rows.append((k, c, b)) }
        }
        return rows.sorted { $0.bytes > $1.bytes }
    }
}
