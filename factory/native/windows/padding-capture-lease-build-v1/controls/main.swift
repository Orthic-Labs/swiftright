import Foundation
func require(_ ok: Bool, _ name: String) { if !ok { fatalError(name) } }
require(try factoryCaptureLeaseNanoseconds([]) == 10_000_000_000, "default10")
require(try factoryCaptureLeaseNanoseconds(["--factory-capture-lease-seconds=40"]) == 40_000_000_000, "explicit40")
for args in [["--factory-capture-lease-seconds=41"], ["--factory-capture-lease-seconds=0"], ["--factory-capture-lease-seconds=40", "--factory-capture-lease-seconds=40"], ["--factory-capture-lease-seconds=15"], ["--factory-capture-lease-seconds=40 "], ["--unknown"], ["40"]] {
    var rejected = false
    do { _ = try factoryCaptureLeaseNanoseconds(args) } catch { rejected = true }
    require(rejected, "invalid lease accepted")
}
print("FACTORY_CAPTURE_LEASE_PURE_CONTROLS positives=2 faults=7")
