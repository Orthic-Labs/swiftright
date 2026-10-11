# Round 1 next-build v2 actual review

Both pinned packages compiled successfully in fresh `build-actual-v2-r1` outputs. Each receipt records exit 0, `ownedExited=true`, natural-exit cleanup with no termination, complete stream drain, PE subsystem 2, exact plan/source/runtime/compiler pins, and matching executable/stdout/stderr hashes.

First missing-metadata preflight, controls exit 255, wrong translated-path failure, and premature-dispatch disposition remain preserved. Actual r4 controls succeeded, then root build-file r2 bound exact control receipt hashes before invoking both builders. SCP acquired eight valid files once; requested `owned-process.json` was absent by design because retained-handle lineage is in `observation.json`; no compiler retry occurred.

Review records receipt-bound process evidence only. No OS-CIM or `ProcessStartInfo` lineage claim is made. Native parity, GUI, executable launch, and test runner remain held.
