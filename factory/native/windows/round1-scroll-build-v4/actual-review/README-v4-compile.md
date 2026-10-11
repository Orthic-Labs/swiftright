# V4 actual compile review

Fetched `build-actual-r1` receipt passes. Receipt hash is `7b4bb2e539b8b635eaf3488f438552ec3d3035a289f68b74c40dcb397028511b`; executable hash is `8be63237c595406036e3869500e7c298781d810b1d78b6eb3ab0242218e7d752`. Compiler exited `0`, timed out `false`, owned process exited naturally, no termination or cleanup error occurred, streams drained, and native window remained unopened. PE subsystem is `2`; compiler stdout is 340 bytes and stderr is empty.

Receipt joins plan `87e220ea…`, source `cd661546…`, runtime commit `37429120…`, runtime tree `c9ce2fb6…`, runtime receipt `b28564f0…`, compiler `1e406093…`, and renderer `e280f4a9…`. Builder source gates bridge membership and all 10 plan bridge bindings. Root build start checked builder, admission, actual admission output, integer output, and reserved-lint hashes before invoking builder. Inline root entry stayed local to preserve reserved-lint membership.

Output SCP transfers all exited `0` and local hashes match. Review was read-only; no compiler, native, SSH, or GUI action occurred here.
