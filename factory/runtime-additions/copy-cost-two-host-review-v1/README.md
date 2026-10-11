# Copy-cost two-host independent review v1

Offline replay verifies Mac 21-file freeze & Windows 198-file freeze, same 52 source files per variant, sole Graph.swift delta, unchanged 175 test methods, raw streams, serialized argv/cwd/process joins & archived runner/compiler bytes. No native rerun occurred.

Both current suites pass 175/175. Both candidate suites pass 174/175: one method fails two assertions (typing <2 ms & scroll <4 ms). Row-edit <15 ms passes. This corrects any historical “173 passed” shorthand; assertion count differs from failed-method count.

Mac medians: current 1.408041 / 2.9175 / 6.821542 ms; candidate 6.347458 / 10.77425 / 6.98075 ms. Windows medians: current 1.9871 / 3.3146 / 3.1923 ms; candidate 6.4876 / 11.5197 / 9.2915 ms (typing / scroll / row edit).

Mac findings: both dynamicLinkage.stdoutSha256 values disagree with frozen otool capture files. XCTest.framework/XCTest archive symlink points into missing Versions/Current; Versions/A target bytes verify. Archived static load-command dependencies establish declared linkage, without runtime loaded-image path receipts. Mac receipt observes Swift driver PID, without independent XCTest child path/PID capture. These gaps do not change raw suite outcomes.

Windows exact runner path/argv appears in CIM descendants; consumed EXE/DLL hashes match copied artifacts. DLL archive/hash joins describe expected compiled input, without independent loaded-image inventory. Timing-start brackets show no external compiler for current, versus 14 & 19 rustc processes for candidate; phase CPU ranges 7–63% / 4–70%. Fixed ordering, unequal hosts/toolchains & ambient activity prevent source-only causal attribution. Candidate remains scratch-only; no production promotion or native qualification.

Versioned reports retain exact producer snapshots & raw-reference pins. `verify_offline.py` performs only file reads, archive decompression & numeric/log accounting. Root-stage manifests list reviewer-owned files.
