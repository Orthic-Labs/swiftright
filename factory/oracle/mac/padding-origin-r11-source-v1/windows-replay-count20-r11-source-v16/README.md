# Fresh r11 coordinator v16

v16 is immutable successor to v12. It propagates explicit `AdmissionRoot` through coordinator, hidden interactive task, dispatch, and capture. Dispatch and capture dot-source versioned first-proof v16 with mandatory UIA schema path, then pass AdmissionRoot into `Assert-PaddingFirstCaptureProof`. Capture supports `-PreflightOnly` without desktop session or lock mutation, so deep source joins run headlessly before any native action.

v12 and r14 source/metadata remain frozen. Root stages these five scripts under one overlay and passes repository AdmissionRoot, ProducerRoot, ControlRoot, RunRoot, OutputRoot, and exact measured receipt pins. Native execution remains pending root review.

Headless admission command is coordinator `-PreflightOnly`; capture may also be invoked directly with `-PreflightOnly` after passing `-AdmissionRoot`. Both paths require `first-proof-fresh-r11-v16.ps1 -UiaSchemaPath <ProducerRoot>\dependencies\uia-worker\schema.ps1`, verify schema hash, and pass `-AdmissionRoot <repository-root>` into first-proof. No lock, scheduled task, desktop session, or native window action occurs during preflight.
