Control03 observed native sample timing & passed known mutation/stall controls. Scope remains independent observational control; GPU completion & physical scanout are unavailable. Single packed-BGRA run supplies observations, without repeatability qualification.

5-second own-PID background run retained289 samples (285complete,4suspended),49 producer mutations &20 distinct validated packed-BGRA hashes across285 pixel reads. Intentional350ms producer stall measured354.737ms; mutation gap355.138ms;21 complete sample callbacks entered during stall. Thus sample delivery continued while producer was stalled.

289/289 CoreMedia host-clock reads fell inside callback-entry mach brackets;289 converted PTS values used native stream synchronization clock. Converted PTS versus SDK WindowServer event differed0..−1 mach tick (0..−41.6667ns). Agreement concerns sample-event clocks only. Duration/decode timestamps were invalid in289/289 samples. Raw callback-entry timestamps precede pixel hashing; processing-return timestamps remain separate.

Exact native source625e13bfa8061a8fbdc73566212995e93cfba6b3688ee09089aea16599bdc256; binary7c356ea631bfee724c369c49908db93df9835b232a5976ef5fb7fbfd7c3f85f8; raw0ec8855c9789914570ef3b83f8d614dd4046f0e049dbed9ebb17913ce1d74eb5. Source-bound Oracle review & launcher hash are archived. Internal executable PID91301 closed its own window; process inventory found0 surviving owned timing processes. Actual appActive/isKeyWindow flags stayed false at window creation. No permission request API was called.

Control01 preparation & Control02 raw/source/binary archives remain preserved. Control02 default planar hashes remain unqualified as pixel identity; its timing/stall observations stand independently. Four outcome regression checks passed: revoked native grant HELD, caught native error FAILED, empty exit0 FAILED, actual completed samples observed.

All source/binary, SDK, review, stdout/stderr, raw timestamps & analysis hashes are indexed in [receipt.json](receipt.json). Current raw samples & full callback age bounds are retained under [control03](evidence/20261011-control-03/analysis.json). Native mutation/stall fault control PASS.
