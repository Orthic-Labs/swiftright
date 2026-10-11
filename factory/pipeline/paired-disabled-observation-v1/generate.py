from __future__ import annotations

import json
from pathlib import Path

from adapter import build_report, load_pinned_inputs

HERE = Path(__file__).resolve().parent
manifest_bytes, payloads = load_pinned_inputs()
report = build_report(manifest_bytes, payloads)
(HERE / "evidence/observational-report.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
md = [
    "# F9 paired disabled observation",
    "",
    "**Status:** observational only; parity held; no promotion.",
    "",
    "One corrected Windows native observation is paired with 20 existing Mac runs for case `swiftui.disabled.recipe/case/f113195a59446fc4`. Zero qualified Windows batches are present.",
    "",
    "Windows UIA reports `Continue` enabled. Mac raw AX reports `Continue` with `AXPress`, but raw Mac AX has no enabled field, so boolean comparison is unavailable. F9 hit-testing remains untested because no input invocation or callback receipt exists.",
    "",
    "Windows viewport correction records ABI 800×1396, actual owned client 800×600 pixels at 240 DPI. Text log records Continue width 160.27344 px, snapped width 160 px, height 60 px, one line. Mac root frame is 79×24 points/pixels; its text renderer channel is empty and resolved font remains held. These measurements retain their native units; no geometry or paint parity is claimed.",
    "",
    "Repeated Mac offscreen captures and identical screenshot hashes are observations, not controlled background-occlusion qualification. Mac raw render intervals and Windows compile duration are reported separately; qualified timing is unavailable.",
    "",
    "Raw input file paths and SHA-256 values are listed in `observational-report.json`; frozen input manifest is `input-manifest.json`.",
]
(HERE / "evidence/OBSERVATION.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print(json.dumps({"case": report["case"]["id"], **report["counts"], "status": report["status"]}, sort_keys=True))
