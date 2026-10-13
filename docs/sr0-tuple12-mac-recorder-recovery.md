# Tuple12 generalized Mac recorder recovery

## Source and unsigned build

Pinned source is commit `0e201571e4320a3b6ccce14313fd2ad67e523904`. `probes/sr0-o/f1-cross/Sources/F1MacRecord/main.swift` is SHA-256 `90de6c1bca7fd114afc754ff2491e8732f9bd8b3922dce76d7aa9e34c7201507`; `Package.swift` is `3a30e1894d6379c2ed5c0cbb60fdeb7046fb29eab915eacea78054118622f92a`. Source accepts `--steps` & reads `plan["steps"]`.

Root may run [prepare-mac-recorder.sh](../qualification/prepare-mac-recorder.sh) with one fresh `$HOME` namespace. It verifies commit-bound bytes, archives pinned package into internal scratch, runs actual `xcrun swift build -c release ... --product F1MacRecord`, then separately resolves `--show-bin-path`; compiler versions, source archive, build logs, binary, & plist are sealed in `unsigned-build-manifest.json`. It never signs, deletes, or overwrites prior output.

## Signing decision

Public SDK review found no public `SecCodeSigner` interface. `SecKeychainSetUserInteractionAllowed(false)` exists only in deprecated `SecKeychain.h` APIs (Xcode 27 RC SDK, lines 634-641); setting it in a parent process cannot establish policy for separately spawned `/usr/bin/codesign`. `kSecUseAuthenticationUIFail` in `SecItem.h` applies `SecItem` queries, not `codesign`; `LAContext.interactionNotAllowed` has same scope. `codesign --dryrun` still generates cryptographic signatures & triggers normal access-control checks, so it cannot prove no prompt.

RightKit release `0.2.153` (`/Volumes/D/claude/rightkit` commit `29e827a6594690762b34bd9f37c9965f6841e32e`) routes SSH/non-Aqua signing through its Aqua signing agent, but agent executes `/usr/bin/codesign` without a no-UI key-use control. New recorder signing is therefore **HELD** until signer owner supplies process-level no-prompt evidence. Do not use stale signed recorder `39ae7c9c...` for captures.

Current checkout read-only audit (`/Volumes/D/claude/rightkit` HEAD `ac16305bc40f89593980c5d2b440669cb7abd9b1`) confirms same boundary: `rightkit-signing-agent.mjs` SHA-256 `4d44db8a19d45a88d3ac60a4e6b664512bae7f6bba9e2cf9157dbdba163acb3a` invokes `/usr/bin/codesign` through `spawnSync`, `shell:false`, bounded timeout, & sanitized environment. No `SecKeychainSetUserInteractionAllowed`, `kSecUseAuthenticationUIFail`, `LAContext`, or equivalent no-prompt control exists in release source/tests. Existing tests prove SSH/non-Aqua routing & reject unlock/password tooling; they do not prove private-key access cannot prompt.

## Admission after signer proof

Use exact identity `Developer ID Application: Adrian D'souza (6KLGD3LLKF)` & identifier `com.orthiclabs.swiftright.f1macrecord`. Preserve fresh app/output namespace. Record new executable SHA-256, bundle-tree SHA-256, CDHash, Authority, TeamIdentifier, timestamp, `codesign --verify --deep --strict` result, source hash, & signer receipt. Existing signed recorder preflight must call `AXIsProcessTrusted()` without options, report trusted state, make zero fixture launches, make zero permission-prompt calls, & pass with nonexistent target. Any new CDHash requires trust admission before capture.
