#!/usr/bin/env python3
"""Export bounded F9 JSON & HTML for an observed Mac20/Windows20 pair."""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

MAX_JSON = 8 * 1024 * 1024
MAX_TEXT = 512


class Hold(ValueError):
    pass


def bounded_json(path: Path, label: str) -> dict:
    if path.is_symlink() or not path.is_file():
        raise Hold(f"{label} missing or symlink")
    if path.stat().st_size > MAX_JSON:
        raise Hold(f"{label} exceeds bounded JSON read")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Hold(f"{label} duplicate JSON key")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"), object_pairs_hook=pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} JSON object required")
    return value


def short(value) -> str:
    if isinstance(value, str):
        return value[:MAX_TEXT]
    if isinstance(value, (int, float, bool)) or value is None:
        return str(value)
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"))[:MAX_TEXT]
    except (TypeError, ValueError):
        return "unserializable"


def row_reason(row: dict) -> str:
    for key in ("issues", "reason", "error", "message", "diagnostics"):
        if key in row and row[key] not in (None, [], ""):
            return f"{key}: {short(row[key])}"
    return "no row reason supplied"


def validate_inputs(pair: dict, mac: dict, reader: dict) -> dict:
    if pair.get("schema") != "factory-native-count20-paired-comparison-v1":
        raise Hold("paired comparison schema required")
    status = pair.get("status")
    if status not in {"blocked-by-protected-production-gate", "reader-observed-rejections", "paired-comparison-observed"}:
        raise Hold("unsupported paired observation status")
    if pair.get("candidateOnly") is not True or pair.get("count") != 20:
        raise Hold("candidate-only Count20 paired observation required")
    parity = pair.get("parity")
    if not isinstance(parity, dict) or parity.get("status") != "held" or parity.get("goldens") != 0 or parity.get("promotion") != "held":
        raise Hold("F9 export requires parity/golden/promotion hold")
    if pair.get("comparisonEligible") is not False:
        raise Hold("F9 export cannot promote comparison eligibility")
    comparison = pair.get("comparison")
    if not isinstance(comparison, dict) or comparison.get("status") != "compared" or not isinstance(comparison.get("verdict"), dict):
        raise Hold("paired production comparator verdict required")
    protected = pair.get("protectedGate")
    if not isinstance(protected, dict) or protected.get("status") not in {"blocked", "not-run"} or not isinstance(protected.get("issues"), list):
        raise Hold("protected gate receipt missing")

    mac_rows = mac.get("macCaptures")
    if mac.get("kind") != "verdict" or not isinstance(mac_rows, list) or len(mac_rows) != 20:
        raise Hold("Mac comparator Count20 input required")
    if mac.get("status") in {"pass", "qualified", "parity-passed", "golden-frozen"}:
        raise Hold("qualified Mac comparator cannot enter held F9 report")
    reader_rows = reader.get("rows")
    if reader.get("count") != 20 or not isinstance(reader_rows, list) or len(reader_rows) != 20:
        raise Hold("trusted reader Count20 input required")
    pair_reader = pair.get("reader")
    if not isinstance(pair_reader, dict) or pair_reader.get("macCount") != 20 or pair_reader.get("windowsCount") != 20:
        raise Hold("paired reader Count20 receipt missing")
    if pair_reader.get("status") != reader.get("status"):
        raise Hold("paired/reader status mismatch")
    pair_rows = pair_reader.get("windowsRows")
    if not isinstance(pair_rows, list) or len(pair_rows) != 20:
        raise Hold("paired Windows row receipt missing")
    for index, (left, right) in enumerate(zip(reader_rows, pair_rows), 1):
        if not isinstance(left, dict) or not isinstance(right, dict) or left.get("status") != right.get("status"):
            raise Hold(f"reader row {index} differs from paired receipt")
    return {"status": status, "protected": protected, "macRows": mac_rows,
            "readerRows": reader_rows, "pairRows": pair_rows, "pairReader": pair_reader}


def build_report(pair: dict, mac: dict, reader: dict, pair_path: Path,
                 mac_path: Path, reader_path: Path) -> dict:
    checked = validate_inputs(pair, mac, reader)
    comparison = pair.get("comparison") if isinstance(pair.get("comparison"), dict) else {}
    verdict = comparison.get("verdict") if isinstance(comparison.get("verdict"), dict) else {}
    semantic = verdict.get("semantic") if isinstance(verdict.get("semantic"), dict) else {}
    semantic_results = semantic.get("results") if isinstance(semantic.get("results"), list) else []
    mac_semantic = mac.get("semantic") if isinstance(mac.get("semantic"), dict) else {}
    mac_results = mac_semantic.get("results") if isinstance(mac_semantic.get("results"), list) else []
    mac_by_channel = {item.get("channel"): item for item in mac_results if isinstance(item, dict)}
    channels = []
    for item in semantic_results:
        if not isinstance(item, dict) or not isinstance(item.get("channel"), str):
            continue
        mac_item = mac_by_channel.get(item["channel"], {})
        difference_hash = item.get("differenceHash")
        channels.append({
            "channel": item["channel"],
            "macStatus": short(mac_item.get("status", "observed")),
            "windowsStatus": short(item.get("status", "missing")),
            "comparisonStatus": short(item.get("status", "missing")),
            "reason": short(item.get("reason") or item.get("details") or "paired comparator result; qualification remains held"),
            "difference": short(difference_hash) if difference_hash else "none emitted",
        })
    if not channels:
        channels = [{"channel": "semantic", "macStatus": short(mac_semantic.get("status", "observed")),
                     "windowsStatus": short(semantic.get("status", "missing")),
                     "comparisonStatus": short(semantic.get("status", "missing")),
                     "reason": "paired semantic channel results absent or blocked",
                     "difference": "none emitted"}]

    verdict_timing = verdict.get("timing") if isinstance(verdict.get("timing"), dict) else {}
    mac_timing = mac.get("timing") if isinstance(mac.get("timing"), dict) else {}
    raw_evidence = verdict_timing.get("rawEvidence") if isinstance(verdict_timing.get("rawEvidence"), list) else []
    timing_rows = []
    for index, row in enumerate(checked["pairRows"], 1):
        if isinstance(row, dict) and any(key in row for key in ("timing", "timingRaw", "lifecycle", "observations")):
            timing_rows.append({"run": index, "status": row.get("status"), "evidenceKeys": [key for key in ("timing", "timingRaw", "lifecycle", "observations") if key in row]})
    protected_reasons = [short(issue) for issue in checked["protected"].get("issues", [])]
    if not protected_reasons:
        protected_reasons = ["protected production gate did not admit cross-platform comparison"]
    report = {
        "schema": "factory-native-count20-f9-observational-report-v1",
        "status": checked["status"],
        "candidateOnly": True,
        "counts": {"macCaptures": 20, "windowsCaptures": 20, "pairedRows": 20,
                    "macComparatorRows": len(checked["macRows"]), "windowsReaderRows": len(checked["readerRows"])},
        "inputs": {"pairedVerdict": str(pair_path), "macComparator": str(mac_path), "trustedReader": str(reader_path)},
        "pairedVerdict": {"status": pair["status"], "comparison": pair.get("comparison"), "readerStatus": checked["pairReader"].get("status"),
                           "semantic": verdict.get("semantic"), "timing": verdict.get("timing"),
                           "repeatability": verdict.get("repeatability")},
        "protectedGate": {"status": checked["protected"].get("status"), "issues": checked["protected"].get("issues", []), "reasons": protected_reasons},
        "channels": channels,
        "timing": {"status": short(verdict_timing.get("status", mac_timing.get("status", "held"))), "boundsHash": verdict_timing.get("boundsHash", mac_timing.get("boundsHash")),
                   "macRawEvidence": [{"id": short(item.get("id")), "hash": short(item.get("hash"))} for item in raw_evidence if isinstance(item, dict)],
                   "macRawEvidenceCount": len(raw_evidence), "windowsRowsWithTimingEvidence": timing_rows,
                   "comparison": "paired comparator timing preserved; provider clocks remain raw and cross-platform timing is not qualified"},
        "differences": {"status": short(semantic.get("status", "held")),
                        "observed": [{"channel": item["channel"], "status": item.get("status"), "differenceHash": item.get("differenceHash")}
                                     for item in semantic_results if isinstance(item, dict) and item.get("differenceHash")],
                        "reasons": ["protected production gate blocked promotion", "paired comparator semantic result is observational", "no parity or golden claim emitted"]},
        "qualification": {"status": "held", "parity": "held", "goldens": 0, "promotion": "held",
                           "reason": "F9 records observed channels only; it does not qualify parity"},
        "readerRows": [{"run": index, "status": row.get("status"), "reason": row_reason(row)} for index, row in enumerate(checked["pairRows"], 1)],
    }
    return report


def render_html(report: dict) -> str:
    esc = lambda value: html.escape(str(value), quote=True)
    channel_rows = "".join(
        f"<tr><td>{esc(item['channel'])}</td><td>{esc(item['macStatus'])}</td><td>{esc(item['windowsStatus'])}</td><td>{esc(item['reason'])}</td><td>{esc(item['difference'])}</td></tr>"
        for item in report["channels"]
    )
    reader_rows = "".join(
        f"<tr><td>{item['run']}</td><td>{esc(item['status'])}</td><td>{esc(item['reason'])}</td></tr>"
        for item in report["readerRows"]
    )
    protected = "<br>".join(esc(item) for item in report["protectedGate"]["reasons"])
    return """<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>F9 paired observation</title><style>body{font:15px/1.45 system-ui,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#18212b}table{border-collapse:collapse;width:100%;font-size:.9rem;margin:1rem 0}th,td{border:1px solid #d5dce5;padding:.4rem;text-align:left;vertical-align:top}th{background:#f1f4f8}.held{color:#8a4b08;font-weight:600}</style><main><h1>F9 paired observation</h1><p><strong>Status:</strong> <span class="held">__STATUS__</span></p><p><strong>Counts:</strong> Mac __MAC__ / Windows __WIN__ / paired __PAIR__</p><p><strong>Protected gate:</strong> __PROTECTED__</p><h2>Channels</h2><table><thead><tr><th>Channel</th><th>Mac</th><th>Windows</th><th>Reason</th><th>Difference</th></tr></thead><tbody>__CHANNELS__</tbody></table><h2>Timing</h2><p>__TIMING__</p><p>Mac raw timing evidence: __TIMING_COUNT__; Windows rows carrying timing evidence: __WINDOW_TIMING__.</p><h2>Windows row observations</h2><table><thead><tr><th>Run</th><th>Status</th><th>Reason</th></tr></thead><tbody>__ROWS__</tbody></table><p>Parity, goldens, &amp; promotion remain held.</p></main></html>""".replace("__STATUS__", esc(report["status"])).replace("__MAC__", esc(report["counts"]["macCaptures"])).replace("__WIN__", esc(report["counts"]["windowsCaptures"])).replace("__PAIR__", esc(report["counts"]["pairedRows"])).replace("__PROTECTED__", protected).replace("__CHANNELS__", channel_rows).replace("__TIMING__", esc(report["timing"]["comparison"])).replace("__TIMING_COUNT__", esc(report["timing"]["macRawEvidenceCount"])).replace("__WINDOW_TIMING__", esc(len(report["timing"]["windowsRowsWithTimingEvidence"]))).replace("__ROWS__", reader_rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--paired", required=True, type=Path)
    parser.add_argument("--mac-report", required=True, type=Path)
    parser.add_argument("--reader-report", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    output = args.output_dir
    if output.exists() and any(output.iterdir()):
        raise SystemExit("HOLD: F9 output must be fresh")
    try:
        pair = bounded_json(args.paired, "paired verdict")
        mac = bounded_json(args.mac_report, "Mac comparator")
        reader = bounded_json(args.reader_report, "trusted reader")
        report = build_report(pair, mac, reader, args.paired, args.mac_report, args.reader_report)
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    output.mkdir(parents=True, exist_ok=True)
    (output / "f9-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output / "f9-report.html").write_text(render_html(report), encoding="utf-8")
    print(json.dumps({"status": report["status"], "macCaptures": 20, "windowsCaptures": 20, "parity": "held", "goldens": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
