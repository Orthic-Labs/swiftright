import CSwiftRightSentinel

public struct SentinelBootstrap: Equatable, Sendable {
    public let structSize: UInt32
    public let abiMajor: UInt32
    public let abiMinor: UInt32
    public let pointerWidth: UInt32
    public let arch: String
    public let fnTableSize: UInt32
}

public enum SentinelError: Error, Equatable, Sendable {
    case queryRejected(code: Int32, callerSize: UInt32)
}

public struct SentinelABIReport: Equatable, Sendable {
    public let expectedSize: UInt32
    public let fullSize: Result<SentinelBootstrap, SentinelError>
    public let tooSmallSize: Result<SentinelBootstrap, SentinelError>
    public let tooSmallCallerSize: UInt32
    public let tooSmallUntouchedStructSize: UInt32?
}


public func sentinelAdd(_ a: Int32, _ b: Int32) -> Int32 {
    swr_sentinel_add(a, b)
}

private func queryBootstrap(callerSize: UInt32) -> (Result<SentinelBootstrap, SentinelError>, UInt32) {
    var info = swr_bootstrap_info()
    info.struct_size = 0xFFFF_FFFF // sentinel value: a rejected call must leave it untouched
    let code = swr_bootstrap_query(&info, callerSize)
    if code != 0 {
        return (.failure(.queryRejected(code: code, callerSize: callerSize)), info.struct_size)
    }
    let arch = withUnsafeBytes(of: info.arch) { raw -> String in
        let bytes = raw.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
    let boot = SentinelBootstrap(
        structSize: info.struct_size,
        abiMajor: info.abi_major,
        abiMinor: info.abi_minor,
        pointerWidth: info.pointer_width,
        arch: arch,
        fnTableSize: info.fn_table_size
    )
    return (.success(boot), info.struct_size)
}

/// Calls swr_bootstrap_query twice: with the correct size and with a deliberately too-small size.
public func checkABI() -> Result<SentinelABIReport, SentinelError> {
    let expected = UInt32(MemoryLayout<swr_bootstrap_info>.size)
    let (full, _) = queryBootstrap(callerSize: expected)
    let tooSmallCaller: UInt32 = 8
    let (small, smallStructSize) = queryBootstrap(callerSize: tooSmallCaller)
    let untouched: UInt32? = {
        if case .failure = small { return smallStructSize }
        return nil
    }()
    return .success(SentinelABIReport(
        expectedSize: expected,
        fullSize: full,
        tooSmallSize: small,
        tooSmallCallerSize: tooSmallCaller,
        tooSmallUntouchedStructSize: untouched
    ))
}
