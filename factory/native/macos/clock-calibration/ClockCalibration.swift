import CoreMedia
import Darwin
import Foundation

func packed(_ time: CMTime) -> [String: Any] {
    ["value": time.value, "timescale": time.timescale,
     "flags": time.flags.rawValue, "epoch": time.epoch]
}

// Headless clock reads only: no AppKit, TCC, windows or capture API.
let destination = CommandLine.arguments[1]
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let host = CMClockGetHostTimeClock()
var records: [[String: Any]] = []
records.reserveCapacity(50001)
records.append(["kind": "metadata", "hostReads": 20000,
                "roundTrips": 30000, "pid": getpid(),
                "machTimebase": ["numer": timebase.numer, "denom": timebase.denom],
                "executable": CommandLine.arguments[0], "scope": "headless host-clock scale calibration"])
for index in 0..<20000 {
    let before = mach_absolute_time()
    let time = CMClockGetTime(host)
    let converted = CMClockConvertHostTimeToSystemUnits(time)
    let after = mach_absolute_time()
    records.append(["kind": "host-read", "index": index,
                    "machBefore": before, "machAfter": after,
                    "hostTime": packed(time), "convertedSystemTicks": converted])
}
let base = mach_absolute_time()
for index in 0..<30000 {
    let ticks = base + UInt64(index)
    let time = CMClockMakeHostTimeFromSystemUnits(ticks)
    let converted = CMClockConvertHostTimeToSystemUnits(time)
    records.append(["kind": "round-trip", "index": index,
                    "inputSystemTicks": ticks, "hostTime": packed(time),
                    "convertedSystemTicks": converted])
}
let handle = FileHandle(forWritingAtPath: destination)!
for record in records {
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    try handle.write(contentsOf: data)
    try handle.write(contentsOf: Data([10]))
}
try handle.close()
