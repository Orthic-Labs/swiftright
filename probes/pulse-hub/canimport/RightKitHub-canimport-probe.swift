// canImport probe (probes/pulse-hub/canimport/Sources/*/probe.swift), mounted inside RightKitHub for this measurement only.
#if canImport(SwiftRightHost)
#warning("CANIMPORT_RESULT RightKitHub canImport(SwiftRightHost)=true")
#else
#warning("CANIMPORT_RESULT RightKitHub canImport(SwiftRightHost)=false")
#endif
internal let canImportSwiftRightHostProbe = true
