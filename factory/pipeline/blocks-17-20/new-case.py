#!/usr/bin/env python3
"""new-case.py <block-dir/case> <Witness.swift> 'Witness_x()' [--appearance aqua|darkAqua|none] [--scheme light|dark|none] [--settle S]
Creates package/ (Windows: Witness.swift + the stamped shared host, not centred, white viewport) and mac-source/ (Witness byte-identical + the blocks-17-20 Mac host)."""
import argparse, subprocess, sys
from pathlib import Path
H = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument("case"); ap.add_argument("witness_file"); ap.add_argument("expr")
ap.add_argument("--appearance", default="aqua", choices=["aqua", "darkAqua", "none"]); ap.add_argument("--scheme", default="light", choices=["light", "dark", "none"]); ap.add_argument("--settle", default="0.3"); ap.add_argument("--alert-host", nargs="?", const="plain", choices=["plain", "text"], help="Windows host with the dialog coordinator: plain = blocks-17-20/shared-windows-host; text = lane B's text-input host (blocks-6-10/text-hosts/windows) with the same coordinator hooks; the Mac host then observes alerts too")
a = ap.parse_args()
case = H / a.case; w = Path(a.witness_file).read_bytes()
(case / "package/Sources/FactoryProbe").mkdir(parents=True, exist_ok=True)
(case / "mac-source/Sources/MacHost").mkdir(parents=True, exist_ok=True)
(case / "package/Sources/FactoryProbe/Witness.swift").write_bytes(w)
(case / "mac-source/Sources/MacHost/Witness.swift").write_bytes(w)
t = (H / "shared-mac-host/CaptureHost.template.swift").read_text()
assert "ScalePin." in t, "Mac host template does not pin the window/displayScale (decision C12; factory/tools/mac-scale-pin/pin_hosts.py)"
(case / "mac-source/Sources/MacHost/CaptureHost.swift").write_text(t.replace("@@WITNESS@@", a.expr).replace("@@SETTLE@@", a.settle).replace("@@APPEARANCE@@", a.appearance).replace("@@SCHEME@@", a.scheme).replace("@@ALERTS@@", "yes" if a.alert_host else "no"))
subprocess.check_call([sys.executable, str(H.parent / "pilot-delivery-five-v1/shared-windows-host/stamp-case.py"), str(case), "--witness", a.expr])
def patch_text_host(t):
    """lane B's text host + the dialog coordinator (the same hooks as blocks-17-20/shared-windows-host); every anchor must match exactly once"""
    def rep(old, new):
        nonlocal t
        assert t.count(old) == 1, ("text host anchor", old[:60], t.count(old))
        t = t.replace(old, new)
    rep("    var windowClosed = false\n", """    var windowClosed = false
    var coordinator: PresentationCoordinator?
    static let leaseNS: UInt64 = {
        for a in CommandLine.arguments where a.hasPrefix("--factory-capture-lease-seconds=") { if let n = UInt64(a.dropFirst("--factory-capture-lease-seconds=".count)), n > 0 { return n * 1_000_000_000 } }
        return 10_000_000_000
    }()
""")
    rep("            self.graph = graph\n", """            self.graph = graph
            coordinator = PresentationCoordinator(graph: graph) { id, title, message, items, defaultIndex in
                try window.requestDialog(requestID: id, title: title, message: message, buttons: items, defaultIndex: defaultIndex)
            }
""")
    rep('            print("HOST_COMMIT version=\\(version) nodes=\\(committed.nodeCount) focused=\\(record.focused ?? "none")")\n', '            print("HOST_COMMIT version=\\(version) nodes=\\(committed.nodeCount) focused=\\(record.focused ?? "none")")\n            try coordinator?.sync(root: root)\n')
    rep("    func event(_ event: BridgeEvent) {\n        guard !windowClosed else { return }\n", "    func event(_ event: BridgeEvent) {\n        guard !windowClosed else { return }\n        if coordinator?.handle(event) == true { graph?.flush(); return }\n")
    rep("if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }", "if time - (started ?? time) > Self.leaseNS { bridge.requestQuit() }")
    return t

if a.alert_host:
    import shutil
    src = case / "package/Sources/FactoryProbe"
    if a.alert_host == "text":
        tpl = patch_text_host((H.parent / "blocks-6-10/text-hosts/windows/CaptureHost.template.swift").read_text()).replace("@@SCRIPT@@", "[]")
    else:
        tpl = (H / "shared-windows-host/CaptureHost.template.swift").read_text()
    (src / "main.swift").write_text(tpl.replace("@@WITNESS@@", a.expr).replace("@@CENTERED@@", "false").replace("@@DARK@@", "false"))
    shutil.copy(H / "shared-windows-host/FactoryViewport.swift", src / "FactoryViewport.swift")
