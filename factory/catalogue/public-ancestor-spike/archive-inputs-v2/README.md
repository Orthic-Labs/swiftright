# F1 archive-inputs-v2

Additive forced-archive mapping for recorded internal probe, request, header, raw-output, receipt, helper, & tool paths. Base v1 mapping remains immutable & is pinned by exact SHA. Main public-ancestor inputs, Swift 16 capture-inputs, Clang owner-guard records, production dependency preimages, & distinct `swift-frontend` tool path are retained with original descriptor path, whole bytes, whole SHA-256, explicit repository archive path, & provenance.

`swift-frontend` uses separate deterministic gzip archive despite byte identity with `swiftc`; this preserves distinct original tool path without alias invention. No process executes archives. Run `python3 verify_archive_inputs.py` & `python3 -m unittest -v test_archive_inputs.py`.
