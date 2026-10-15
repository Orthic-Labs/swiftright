// Round 5 probe packaging only (not a SwiftRight gap): PulseHub's Package.swift declares a resource bundle (Tanker, whose licence is unconfirmed and which is not bundled
// here), so `Bundle.module` does not exist in this probe package. It answers the main bundle, which holds no Tanker: the hub then takes its documented system fallback.
import Foundation
extension Bundle { static var module: Bundle { .main } }
