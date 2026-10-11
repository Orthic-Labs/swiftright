# Seeded hosts source review

Five package plans are exact and internally joined: package source bindings match local files, each witness manifest matches its plan, and all plans share runtime commit `37429120…`, runtime tree `c9ce2fb6…`, runtime receipt `b28564f0…`, verifier `a134d0bf…`, compiler `1e406093…`, renderer `e280f4a9…`, and 10 exact bridge bindings. No aliases or cross-case source substitutions were found.

Strict Mac joining is correctly blocked. Every plan records `Mac20SourceBinding: false`; existing Mac captures carry different source hashes. `verify_mac_join.py` requires 20 distinct paths, exact integer runs 1..20, exact case and exact sourceHash. Its six synthetic faults are covered by `pure-controls/test_mac_join.py`. Fresh exact-source Mac20 captures are required before any parity or join claim.

Compiler-only design has no GUI or native launch, but current `build-hosts.ps1` is not cleared for execution under retained-handle policy: cleanup uses PID lookup and `taskkill /PID /T /F`, with no retained kernel handle, stream-drain receipt, or unresolved descendant timeout refusal. Repair this guard before compile-only host runs; source package preparation may continue while Mac recapture is pending.

Stage hash: `f23648e19fb807c78a83c52b208147999c3defc5621962135a1feeab385c4b46`. Builder hash: `3369565dbeb453b95ee589b9dccf33459c4c736b16bc862fb89c5b9ccbead410`. Verifier hash: `a876698ef058172ae54284dae4fa983b86ed4196cf6ede285435a436b7dc541a`.
