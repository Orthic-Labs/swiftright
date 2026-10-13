# Cleanup rehydration v2 independent review

Offline review confirms v2 helper source, 5 controls, replay receipt & 0644 data-only output hashes. Existing v2 cache is reused without copying 173 MB frontend bytes.

Review config replaces xcrun, swiftc & swift-frontend mappings in 423-entry live origin map with v2 cache targets. Production `ArchiveByteReader` reads all 3 replacements, then `workflow.collect` verifies fresh Mac20 with 180 origin descriptors & `workflow.gate_evidence` replays offline as blocked. No native/compiler execution occurred.

Output: `root-replay-r2/`. Internal review config & v2 cache remain for root cleanup after consumers finish. Live origin config & fresh capture bytes remain unchanged.
