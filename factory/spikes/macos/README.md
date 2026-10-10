# macOS capture spike

Independent, new-file-only SR1 F5 spike. It requires macOS 15+ & records only observations it actually receives.

```sh
swift build --scratch-path .build-spike
swift run --scratch-path .build-spike mac-capture-spike
```

Structural mode is non-windowed. It uses `ImageRenderer` to invoke a `TextRenderer` & custom `Layout`; it never invokes ScreenCaptureKit.

Inside a disposable Tart guest only, after Screen Recording & Accessibility are already provisioned, run:

```sh
swift run --scratch-path .build-spike mac-capture-spike --vm-capture
```

VM capture starts only when `sysctl kern.hv_vmm_present` is `1` & `sysctl hw.model` begins `VirtualMac`; host execution cannot create its window. It makes one PID-titled, process-owned window, presents one popover, asks ScreenCaptureKit for a compositor image, starts sibling `mac-capture-ax-client` for separate-process AX observation with a four-second timeout, emits JSON, then closes its window & popover. Run whole VM process under a 25-second external bound because ScreenCaptureKit permission discovery has no reliable cancellation guarantee. It reports popover presentation state but does not classify popover pixels. It has no renderer, bridge, ABI or golden integration.
