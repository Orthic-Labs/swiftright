# Seeded native v5 factory repair

Clones frozen v4 source inputs. Runtime, renderer, ABI, host witnesses, frozen host plans & Mac source proof unchanged.

Retained kernel exit certification remains typed booleans + integer WAIT_OBJECT_0 value0 + exact certification/terminal status. Process exit15s, raw copy5s & separate destination closure5s deadlines unchanged.

Capture & coordinator use shared Get-FactoryRawHash gate. Hash callback runs only after typed confirmed destination closure & completed managed close-worker authority. Unclosed destinations return null SHA, unqualified status & explicit reason. Coordinator blocks fallback release for unqualified raw state.

Raw closure snapshots are detached from later helper updates. Closure timeout stays recorded after eventual cleanup; recovered closed bytes remain diagnostic partial. Required flush failure cannot seal.

Existing eight control entries retained. test-kernel-bounds.ps1 additionally runs stream-seal controls. Actual close-timeout control holds managed worker behind ManualResetEvent before Flush/Dispose, expires1ms test deadline, verifies capture & deserialized coordinator gates invoke zero hash callbacks, then releases worker for bounded cleanup. Earlier strict kernel/status, failed-flush,384KiB console &64KiB inherited-writer controls remain.

Windows PowerShell5 AST & actual controls are pending root execution. Stage is ready for independent source review.
