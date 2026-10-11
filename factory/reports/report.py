"""Render local, evidence-aware per-block factory reports."""

from __future__ import annotations

import html
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from factory.core.artifacts import canonical_hash


CHANNELS = ("layout", "paint", "hit-testing", "accessibility-provider",
            "accessibility-external", "focus", "text", "events-state",
            "animation", "presentation")
_CHANNEL_ARRAYS = {
    "layout": "layout", "paint": "images", "accessibility-provider": "ax",
    "accessibility-external": "ax", "text": "text", "events-state": "events",
    "animation": "anim",
}


def _collection(value: Any, key: str, label: str) -> list[dict]:
    if isinstance(value, list):
        rows = value
    elif isinstance(value, dict) and isinstance(value.get(key), list):
        rows = value[key]
    elif isinstance(value, dict) and value.get("kind") == {"cases": "case", "captures": "capture", "verdicts": "verdict", "receipts": "receipt"}.get(key):
        rows = [value]
    else:
        raise TypeError(f"{label} must be a list or an object containing a {key!r} list")
    if any(not isinstance(row, dict) for row in rows):
        raise TypeError(f"{label} entries must be objects")
    return rows


def _ref_id(value: Any) -> str | None:
    return value.get("id") if isinstance(value, dict) else None


def _synthetic(*values: Any) -> bool:
    serialized = json.dumps(values, sort_keys=True, ensure_ascii=False).lower()
    return "synthetic" in serialized or "spec-example" in serialized


def _safe_slug(identifier: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", identifier).strip(".-") or "block"
    return slug[:100]


def _md(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ").replace("<", "&lt;").replace(">", "&gt;")


def _compact(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _count_records(capture: dict, channel: str) -> int:
    if channel == "hit-testing":
        return sum(1 for event in capture.get("events", []) if "hit" in str(event.get("kind", "")).lower())
    if channel == "focus":
        return sum(1 for event in capture.get("events", []) if "focus" in str(event.get("kind", "")).lower())
    if channel == "presentation":
        return sum(len(anim.get("presentedFrames", [])) for anim in capture.get("anim", []) if isinstance(anim, dict))
    array = _CHANNEL_ARRAYS.get(channel)
    if array is None:
        return 0
    records = capture.get(array, [])
    if channel == "accessibility-provider":
        return sum(1 for row in records if row.get("source") == "provider")
    if channel == "accessibility-external":
        return sum(1 for row in records if row.get("source") == "external")
    return len(records) if isinstance(records, list) else 0


def _channel_values(verdict: dict) -> dict[str, str]:
    semantic = verdict.get("semantic", {})
    results = semantic.get("results", []) if isinstance(semantic, dict) else []
    return {str(item.get("channel")): f"{item.get('status', 'missing')}" + (f" · {item['differenceHash']}" if item.get("differenceHash") else "")
            for item in results if isinstance(item, dict)}


def _capture_tuple_matches(capture_tuple: Any, verdict_tuple: Any, platform: str) -> bool:
    if not isinstance(capture_tuple, dict) or not isinstance(verdict_tuple, dict):
        return False
    if capture_tuple == verdict_tuple:
        return True
    shared = ("id", "sdk", "macosBuild", "toolchains", "runtimeCommit", "rendererHash", "factoryVersion", "acceptanceConfigHash")
    if any(capture_tuple.get(key) != verdict_tuple.get(key) for key in shared):
        return False
    host_hashes = verdict_tuple.get("hostHashes")
    if not isinstance(host_hashes, dict):
        return False
    expected_host = host_hashes.get(platform)
    # Capture schema example binds only the executing host's hash; accept that
    # documented projection as well as the full verdict tuple above.
    return expected_host is not None and capture_tuple.get("hostHashes") == {platform: expected_host}


def _resolve_capture_set(refs: Any, captures: list[dict], platform: str, case_ref: dict,
                        tuple_value: dict) -> tuple[list[dict], str]:
    if not isinstance(refs, list) or len(refs) != 20:
        return [], f"Expected 20 {platform} capture references"
    ids = [_ref_id(ref) for ref in refs]
    if any(not isinstance(ref, dict) or not isinstance(ref.get("hash"), str) for ref in refs) or len(set(ids)) != 20:
        return [], f"{platform} capture references are missing or duplicated"
    by_id: dict[str, list[dict]] = defaultdict(list)
    for capture in captures:
        if isinstance(capture.get("id"), str):
            by_id[capture["id"]].append(capture)
    resolved = []
    for ref in refs:
        matches = by_id.get(ref["id"], [])
        if len(matches) != 1:
            return [], f"{platform} capture reference does not resolve uniquely"
        capture = matches[0]
        if capture.get("platform") != platform:
            return [], f"Capture {ref['id']} has wrong platform"
        if canonical_hash(capture) != ref.get("hash"):
            return [], f"Capture {ref['id']} hash does not match artifact"
        if capture.get("case") != case_ref:
            return [], f"Capture {ref['id']} is bound to another case or case hash"
        if not _capture_tuple_matches(capture.get("tuple"), tuple_value, platform):
            return [], f"Capture {ref['id']} tuple does not match verdict tuple"
        resolved.append(capture)
    runs = [capture.get("meta", {}).get("run") if isinstance(capture.get("meta"), dict) else None for capture in resolved]
    if any(not isinstance(run, int) or isinstance(run, bool) for run in runs):
        return [], f"{platform} capture run numbers are invalid"
    if set(runs) != set(range(1, 21)):
        return [], f"{platform} capture runs must uniquely cover 1 through 20"
    return resolved, ""


def _repeatability_matches(repeat: Any, refs: list[dict]) -> bool:
    if not isinstance(repeat, dict) or repeat.get("runs") != 20 or repeat.get("semanticAgreement") is not True:
        return False
    evidence = repeat.get("evidence")
    if not isinstance(evidence, list) or len(evidence) != 20:
        return False
    normalize = lambda rows: sorted((row.get("id"), row.get("hash")) for row in rows if isinstance(row, dict))
    return len(normalize(evidence)) == 20 and normalize(evidence) == normalize(refs)


def _bound_gate_receipt_matches(receipts: list[dict], case_ref: dict, tuple_value: dict,
                                mac_refs: list[dict], win_refs: list[dict]) -> bool:
    expected_hashes = {case_ref["hash"], *(ref.get("hash") for ref in mac_refs), *(ref.get("hash") for ref in win_refs)}
    for receipt in receipts:
        provenance = receipt.get("provenance", {})
        if not isinstance(provenance, dict):
            continue
        if (receipt.get("kind") != "receipt" or receipt.get("operation") != "gate"
                or receipt.get("status") != "pass" or receipt.get("tuple") != tuple_value
                or provenance.get("producer") != "factory.gate/0.1"):
            continue
        inputs = receipt.get("inputs", [])
        input_hashes = {row.get("hash") for row in inputs if isinstance(row, dict)} if isinstance(inputs, list) else set()
        outputs = receipt.get("outputs", [])
        gate_output = any(isinstance(row, dict) and str(row.get("id", "")).startswith("gate.f10.")
                          and isinstance(row.get("hash"), str) for row in outputs) if isinstance(outputs, list) else False
        if expected_hashes <= input_hashes and gate_output:
            return True
    return False


def _case_status(case: dict, verdict: dict | None, captures: list[dict], gate_receipts: list[dict] | None = None) -> tuple[str, str]:
    case_id = str(case.get("id", "unnamed-case"))
    if verdict is None:
        return "blocked", "No verdict for manifest case"
    status = str(verdict.get("status", "blocked"))
    mac_refs = verdict.get("macCaptures", [])
    win_refs = verdict.get("windowsCaptures", [])
    if not isinstance(mac_refs, list):
        mac_refs = []
    if not isinstance(win_refs, list):
        win_refs = []
    mac = [capture for capture in captures if capture.get("platform") == "macos" and capture.get("id") in {_ref_id(ref) for ref in mac_refs}]
    win = [capture for capture in captures if capture.get("platform") == "windows" and capture.get("id") in {_ref_id(ref) for ref in win_refs}]
    if status == "pass":
        if _synthetic(case, verdict, mac, win):
            return "blocked", "Synthetic/spec-example evidence cannot establish parity"
        case_ref = {"id": case_id, "hash": canonical_hash(case)}
        if verdict.get("case") != case_ref:
            return "blocked", "Verdict case reference does not match manifest case hash"
        tuple_value = case.get("tuple")
        if not isinstance(tuple_value, dict) or verdict.get("tuple") != tuple_value:
            return "blocked", "Verdict tuple does not match manifest case tuple"
        mac, reason = _resolve_capture_set(mac_refs, captures, "macos", case_ref, tuple_value)
        if reason:
            return "blocked", reason
        win, reason = _resolve_capture_set(win_refs, captures, "windows", case_ref, tuple_value)
        if reason:
            return "blocked", reason
        semantic = verdict.get("semantic", {})
        results = semantic.get("results", []) if isinstance(semantic, dict) else []
        channels = [item.get("channel") for item in results if isinstance(item, dict)]
        if semantic.get("status") != "pass" or not channels or any(item.get("status") != "pass" for item in results if isinstance(item, dict)):
            return "blocked", "Pass verdict has no passing semantic channel observations"
        timing = verdict.get("timing", {})
        if not isinstance(timing, dict) or timing.get("status") != "pass":
            return "blocked", "Pass verdict lacks passing timing evidence"
        repeatability = verdict.get("repeatability", {})
        if not isinstance(repeatability, dict) or not _repeatability_matches(repeatability.get("mac"), mac_refs):
            return "blocked", "Mac repeatability evidence does not bind 20 capture runs"
        if not _repeatability_matches(repeatability.get("windows"), win_refs):
            return "blocked", "Windows repeatability evidence does not bind 20 capture runs"
        for channel in channels:
            if any(not _count_records(capture, str(channel)) for capture in mac):
                return "blocked", f"Mac has no {channel} records for passing channel"
            if any(not _count_records(capture, str(channel)) for capture in win):
                return "blocked", f"Windows has no {channel} records for passing channel"
        if not _bound_gate_receipt_matches(gate_receipts or [], case_ref, tuple_value, mac_refs, win_refs):
            return "blocked", "Supplied passing F10 receipt bound to case, captures & tuple is required"
    if status not in {"pass", "fail", "blocked", "invalidated"}:
        return "blocked", f"Unknown verdict status: {status}"
    return status, ""


def _capture_label(captures: list[dict], platform: str, refs: list[dict]) -> str:
    ref_by_id = {_ref_id(ref): ref.get("hash") for ref in refs if _ref_id(ref)}
    ids = set(ref_by_id)
    found = [capture for capture in captures if capture.get("platform") == platform and capture.get("id") in ids]
    if not found:
        return "missing capture"
    counts = {channel: sum(_count_records(capture, channel) for capture in found) for channel in CHANNELS}
    names = ", ".join(f"{capture.get('id', 'unnamed')} [{ref_by_id.get(capture.get('id'), 'no reference hash')}]" for capture in found)
    summary = ", ".join(f"{channel}={count}" for channel, count in counts.items())
    return f"{names} · {summary}"


def _block_markdown(block: dict, cases: list[dict], captures: list[dict], verdicts_by_case: dict[str, dict], demands: list[str], gate_receipts: list[dict]) -> tuple[str, Counter]:
    bid = str(block.get("id", "unnamed-block"))
    rows = []
    counts: Counter = Counter()
    for case in cases:
        cid = str(case.get("id", "unnamed-case"))
        verdict = verdicts_by_case.get(cid)
        relevant = case.get("block") == bid
        if not relevant:
            continue
        status, reason = _case_status(case, verdict, captures, gate_receipts)
        counts[status] += 1
        if verdict is None:
            mac_refs, win_refs = [], []
        else:
            mac_refs, win_refs = verdict.get("macCaptures", []), verdict.get("windowsCaptures", [])
        values = _channel_values(verdict or {})
        channel_cells = "; ".join(f"{name}: {values.get(name, 'held / no verdict channel')}" for name in CHANNELS)
        if not verdict:
            channel_cells = "held / no verdict"
        rows.append((cid, status, reason,
                     _capture_label(captures, "macos", mac_refs),
                     _capture_label(captures, "windows", win_refs), channel_cells))
    total = len(cases)
    # Case manifest denominator is block-specific; unrelated cases do not dilute coverage.
    block_cases = [case for case in cases if case.get("block") == bid]
    total = len(block_cases)
    status = "no manifest cases" if total == 0 else ("pass" if counts["pass"] == total else "fail" if counts["fail"] else "blocked")
    evidence_tag = "synthetic/spec-example" if any(_synthetic(case, verdicts_by_case.get(str(case.get("id", "")))) for case in block_cases) else "unmarked"
    caps = block.get("capabilities", [])
    if not caps:
        caps = []
    lines = [f"# {bid}", "", f"**Status:** {status}  ",
             f"**Manifest cases:** {counts['pass']} pass / {counts['fail']} fail / {counts['blocked']} blocked / {counts['invalidated']} invalidated / {total} total  ",
             f"**Inventory:** {block.get('inventoryStatus', 'unknown')} · **Progress:** {block.get('progress', 'unknown')}  ",
             f"**Symbols:** {', '.join(map(str, block.get('symbols', []))) or 'none'}  ",
             f"**Capabilities:** {', '.join(demands) or ', '.join(map(str, caps)) or 'unspecified'}  ",
             f"**Evidence label:** {evidence_tag}", ""]
    if rows:
        lines.extend(["| Manifest case | Status | Mac reference & channel counts | Windows reference & channel counts | Diff / channel values |", "|---|---|---|---|---|"])
        for cid, case_status, reason, mac, win, values in rows:
            lines.append("| " + " | ".join(_md(item) for item in (cid, f"{case_status}" + (f": {reason}" if reason else ""), mac, win, values)) + " |")
    else:
        lines.append("No cases are assigned to this block in supplied manifest.")
    lines.extend(["", "Empty capture arrays mean no observation for that channel; they never count as equal values. Missing captures & channels are held. Only paired, non-synthetic captures with records can support a passing verdict.", ""])
    return "\n".join(lines), counts


def _inline_html(value: str) -> str:
    escaped = html.escape(value, quote=True)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    link_re = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

    def link(match):
        label, href = match.groups()
        if href.startswith("blocks/") and ".." not in href and not href.startswith("/"):
            return f'<a href="{html.escape(href, quote=True)}">{label}</a>'
        return label

    return link_re.sub(link, escaped)


def _render_markdown(markdown: str) -> str:
    lines = markdown.splitlines()
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("# "):
            out.append(f"<h1>{_inline_html(line[2:])}</h1>")
        elif line.startswith("## "):
            out.append(f"<h2>{_inline_html(line[3:])}</h2>")
        elif line.startswith("| ") and i + 1 < len(lines) and lines[i + 1].startswith("|---"):
            def cells(row):
                return [cell.strip().replace("\\|", "|") for cell in re.split(r"(?<!\\)\|", row.strip().strip("|"))]

            headers = cells(line)
            i += 2
            body_rows = []
            while i < len(lines) and lines[i].startswith("| "):
                body_rows.append(cells(lines[i]))
                i += 1
            head = "".join(f"<th>{_inline_html(cell)}</th>" for cell in headers)
            body = "".join("<tr>" + "".join(f"<td>{_inline_html(cell)}</td>" for cell in row) + "</tr>" for row in body_rows)
            out.append(f"<div class=\"table-wrap\"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>")
            continue
        else:
            out.append(f"<p>{_inline_html(line)}</p>")
        i += 1
    return "\n".join(out)


def _html_page(title: str, markdown: str, css: str = "") -> str:
    content = _render_markdown(markdown)
    return "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>" + html.escape(title) + "</title><style>body{font:15px/1.5 system-ui,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#18212b}table{border-collapse:collapse;width:100%;font-size:.9rem}th,td{border:1px solid #d5dce5;padding:.45rem;text-align:left;vertical-align:top}th{background:#f1f4f8}.table-wrap{overflow-x:auto}a{color:#0757a6}" + css + "</style><main>" + content + "</main></html>\n"


def build_report(registry, cases, captures, verdicts, output_dir, demand=None, *, gate_receipts=None):
    """Write Markdown & HTML dashboard plus one report per registered block.

    ``cases`` is the fixed denominator; observed-only captures never add or
    remove cases. Return paths for generated index and per-block files.
    """
    if not isinstance(registry, dict) or not isinstance(registry.get("blocks"), list):
        raise TypeError("registry must be a block-registry object with blocks list")
    case_rows = _collection(cases, "cases", "cases")
    capture_rows = _collection(captures, "captures", "captures")
    verdict_rows = _collection(verdicts, "verdicts", "verdicts")
    receipt_rows = _collection(gate_receipts, "receipts", "gate receipts") if gate_receipts is not None else []
    if demand is not None and not isinstance(demand, dict):
        raise TypeError("demand must be an object")
    unmapped_demands = (demand or {}).get("unmappedDemands", [])
    if not isinstance(unmapped_demands, list) or any(not isinstance(row, dict) for row in unmapped_demands):
        raise TypeError("demand.unmappedDemands must be a list of objects")
    for row in unmapped_demands:
        status = row.get("status")
        if (not isinstance(row.get("demand"), str) or not row["demand"]
                or row.get("registry_block_id") is not None
                or not isinstance(status, str) or status not in {"unmapped", "source_inventory_only"}):
            raise ValueError("unmapped demand rows must retain text, null registry_block_id, and an unmapped status")
    if any(not isinstance(block, dict) for block in registry["blocks"]):
        raise TypeError("registry blocks must be objects")
    verdicts_by_case = {}
    for verdict in verdict_rows:
        case_id = _ref_id(verdict.get("case"))
        if case_id:
            verdicts_by_case[case_id] = verdict
    capabilities = (demand or {}).get("blockCapabilities", {})
    if not isinstance(capabilities, dict):
        raise TypeError("demand.blockCapabilities must be an object")
    journeys = (demand or {}).get("journeys", [])
    if not isinstance(journeys, list):
        raise TypeError("demand.journeys must be a list")
    journey_map: dict[str, list[str]] = defaultdict(list)
    for journey in journeys:
        if not isinstance(journey, dict) or not isinstance(journey.get("blocks", []), list):
            raise TypeError("each demand journey must be an object with blocks list")
        jid = str(journey.get("name", journey.get("id", "unnamed journey")))
        for bid in journey.get("blocks", []):
            journey_map[str(bid)].append(jid)

    out = Path(output_dir)
    block_dir = out / "blocks"
    block_dir.mkdir(parents=True, exist_ok=True)
    report_paths = []
    dashboard_counts: Counter = Counter()
    capability_counts: dict[str, Counter] = defaultdict(Counter)
    dashboard_rows = []
    used: set[str] = set()
    for block in registry["blocks"]:
        bid = str(block.get("id", "unnamed-block"))
        assigned_caps = capabilities.get(bid, [])
        if not isinstance(assigned_caps, list):
            raise TypeError(f"demand.blockCapabilities[{bid!r}] must be a list")
        md, counts = _block_markdown(block, case_rows, capture_rows, verdicts_by_case, [str(x) for x in assigned_caps], receipt_rows)
        total = sum(counts.values())
        status = "no manifest cases" if total == 0 else ("pass" if counts["pass"] == total else "fail" if counts["fail"] else "blocked")
        synthetic_evidence = any(_synthetic(case, verdicts_by_case.get(str(case.get("id", "")))) for case in case_rows if case.get("block") == bid)
        if synthetic_evidence:
            dashboard_counts["synthetic"] += 1
        dashboard_counts[status] += 1
        for capability in assigned_caps:
            capability_counts[str(capability)][status] += 1
        slug = _safe_slug(bid)
        if slug in used:
            import hashlib
            slug = f"{slug}-{hashlib.sha256(bid.encode()).hexdigest()[:8]}"
        used.add(slug)
        md_path, html_path = block_dir / f"{slug}.md", block_dir / f"{slug}.html"
        md_path.write_text(md, encoding="utf-8")
        html_path.write_text(_html_page(bid, md), encoding="utf-8")
        report_paths.append({"block": bid, "markdown": str(md_path), "html": str(html_path)})
        dashboard_rows.append((bid, status, "synthetic/spec-example" if synthetic_evidence else "unmarked", total, counts["pass"], counts["fail"], counts["blocked"] + counts["invalidated"], assigned_caps, journey_map.get(bid, []), f"blocks/{slug}.md"))

    lines = ["# SwiftRight factory report", "", "Local report generated from supplied registry, fixed case manifest, captures & verdicts.", "",
             "Status counts use registered blocks; case counts use the fixed manifest per block. Synthetic inputs are identified and cannot establish parity.", "",
             "## Dashboard", "", f"**Blocks:** {len(registry['blocks'])} · **Passing:** {dashboard_counts['pass']} · **Failing:** {dashboard_counts['fail']} · **Blocked:** {dashboard_counts['blocked']} · **Synthetic:** {dashboard_counts['synthetic']} · **No manifest cases:** {dashboard_counts['no manifest cases']}", "",
             "| Block | Status | Evidence label | Cases pass / fail / blocked / total | Capabilities | Shell demand | Report |", "|---|---|---|---:|---|---|---|"]
    for bid, status, evidence, total, passed, failed, held, caps, demanded_journeys, relpath in dashboard_rows:
        lines.append(f"| {_md(bid)} | {status} | {evidence} | {passed} / {failed} / {held} / {total} | {_md(', '.join(map(str, caps)) or 'unspecified')} | {_md(', '.join(demanded_journeys) or 'none mapped')} | [{_md(relpath)}]({relpath}) |")
    lines.extend(["", "## Capability status", "", "| Capability | Passing blocks | Failing blocks | Blocked or synthetic blocks |", "|---|---:|---:|---:|"])
    if capability_counts:
        for name, counts in sorted(capability_counts.items()):
            lines.append(f"| {_md(name)} | {counts['pass']} | {counts['fail']} | {counts['blocked'] + counts['synthetic']} |")
    else:
        lines.append("| No capability mapping supplied | 0 | 0 | 0 |")
    lines.extend(["", "## Shell demand", "", "| Journey | Blocks in registry | Passing blocks | Held/failed/synthetic blocks |", "|---|---:|---:|---:|"])
    if journeys:
        for journey in journeys:
            jid = str(journey.get("name", journey.get("id", "unnamed journey")))
            journey_blocks = [str(bid) for bid in journey.get("blocks", [])]
            known = {row[0]: row[1] for row in dashboard_rows}
            lines.append(f"| {_md(jid)} | {sum(b in known for b in journey_blocks)} | {sum(known.get(b) == 'pass' for b in journey_blocks)} | {sum(known.get(b) != 'pass' for b in journey_blocks)} |")
    else:
        lines.append("| No demand map supplied | 0 | 0 | 0 |")
    if unmapped_demands:
        status_counts = Counter(row["status"] for row in unmapped_demands)
        lines.extend(["", f"## Unmapped extended demands ({len(unmapped_demands)})", "",
                      f"Statuses: {status_counts['unmapped']} unmapped; {status_counts['source_inventory_only']} source-inventory-only. Registry mapping remains null.", "",
                      "| Demand | Status | Registry block |", "|---|---|---|"])
        for row in unmapped_demands:
            lines.append(f"| {_md(row['demand'])} | {_md(row['status'])} | unmapped |")
    elif demand is not None and "unmappedDemands" in demand:
        lines.extend(["", "## Unmapped extended demands", "", "None."])
    lines.extend(["", "No publishing is performed. HTML escapes all supplied artifact text; filenames use sanitized block IDs.", ""])
    index_md = out / "index.md"
    index_html = out / "index.html"
    index_md.write_text("\n".join(lines), encoding="utf-8")
    index_html.write_text(_html_page("SwiftRight factory report", "\n".join(lines)), encoding="utf-8")
    return {"markdown": str(index_md), "html": str(index_html), "blocks": report_paths}
