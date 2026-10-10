# Independent host lanes

These hosts support capture-method spikes only. They do not consume or qualify SR0's frozen ABI or contract.

## Mac VM used on 10 October 2026

Tart binary: `/Volumes/D/tart-install/dl/tart.app/Contents/MacOS/tart`.
Existing stopped `sliceapp-base`: `/Volumes/D/tart-home/vms/sliceapp-base`.
Factory-owned working storage: `factory/.tart` (ignored). Existing base & SR0 files remain unchanged.

Provision a fresh independent lane by APFS-copying `config.json`, `nvram.bin` & `disk.img` into a new
`factory/.tart/vms/base-snapshot` directory, then invoke `tart clone base-snapshot sr1-capture` with
`TART_HOME` set to absolute factory `.tart` path & `TART_NO_AUTO_PRUNE=1`. Use a fresh destination; never overwrite
another lane. Tart clone regenerates network identity before use. Copying a disk is provisioning, not capture evidence.

Start only factory's clone:

```sh
export TART_HOME="$PWD/factory/.tart"
export TART_NO_AUTO_PRUNE=1
/Volumes/D/tart-install/dl/tart.app/Contents/MacOS/tart run sr1-capture \
  --no-graphics --no-audio --no-clipboard --no-usb-accessories
```

The hidden VM gets no host directory shares. Query `tart ip sr1-capture --wait 30`; use existing provisioned
`/Volumes/D/tart-home/keys/vmkey` for `admin` SSH, batch mode, bounded connection timeout & a factory-local
known-hosts file. Do not disable host-key checks. Never launch a capture window on user's host Mac.

Observed guest: macOS 26.6.2 (`25G83`), `kern.hv_vmm_present=1`, `hw.model=VirtualMac2,1`, console user `admin`,
running WindowServer. Screen Recording, AX access, active render surface & presented-frame capture remain separate
preflight requirements. A running VM or successful compile does not establish those capabilities.

Copy factory's `mac-capture-spike` & sibling `mac-capture-ax-client` binaries into guest `~/factory/`; verify both
SHA-256 hashes on both sides. Preserve machine-readable output under `factory/hosts/evidence/` with binary/source
hashes. Bound guest execution externally: framework cancellation alone does not guarantee a process deadline.
Stop only `sr1-capture` after spike work:

```sh
/Volumes/D/tart-install/dl/tart.app/Contents/MacOS/tart stop sr1-capture
```

## Dell

[Session spike](../spikes/windows/RESULT.md) records Windows 11 Pro inventory & second-session feasibility.
Take `D:\Claude\desktop.lock` before every windowed run using the existing SR0 lock protocol. Do not steal, clear or
rewrite another owner's lock. Ordinary tests use window-targeted input & background windows; IME/Narrator use
foreground checks & abort-on-focus-loss within the held lane. Native-only tests currently use shared desktop.

No file deletion over SSH. This turn's Dell preflight was read-only apart from adding its script under
`D:\Claude\swiftright\factory\spikes\windows`; no test window or native input was launched.
