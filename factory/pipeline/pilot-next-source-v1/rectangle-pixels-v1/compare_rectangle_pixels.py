#!/usr/bin/env python3
"""Compare measured Mac compositor & Windows PrintWindow rectangle pixels.

This reader consumes only explicit, hash-bound archive rows. It never captures,
infers AX/provider semantics, or rewrites raw evidence.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from collections import Counter
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
MAX_IMAGE = 8 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
MAX_PIXELS = 4_000_000
SHA = re.compile(r"^sha256:[0-9a-f]{64}$")

class ComparisonError(ValueError):
    pass

def bounded_json(path: Path):
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ComparisonError(f"bounded JSON required: {path}")
    return json.loads(path.read_bytes())

def canonical_json(path: Path):
    """Load canonical artifact JSON after bounded stat; reject ambiguous JSON."""
    try:
        from factory.tools.canonical_json import loads
    except ImportError as exc:
        raise ComparisonError("factory canonical JSON loader unavailable") from exc
    try:
        return loads(path.read_bytes())
    except Exception as exc:
        raise ComparisonError(f"canonical JSON invalid: {path}: {exc}") from exc

def canonical_hash(value) -> str:
    try:
        from factory.tools.canonical_json import sha256
    except ImportError as exc:
        raise ComparisonError("factory canonical hash unavailable") from exc
    try:
        return sha256(value)
    except Exception as exc:
        raise ComparisonError(f"canonical artifact hash failed: {exc}") from exc

def stream_hash(path: Path, limit: int = MAX_IMAGE) -> tuple[int, str]:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise ComparisonError(f"bounded regular image required: {path}")
    digest = hashlib.sha256(); total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk); digest.update(chunk)
    return total, "sha256:" + digest.hexdigest()

def repo_file(repo: Path, raw: str) -> Path:
    if not isinstance(raw, str) or not raw or raw.startswith(("/", "\\")) or "\\" in raw or ":" in raw:
        raise ComparisonError("archive path must be repository-relative")
    parts = Path(raw).parts
    if any(part in ("", ".", "..") for part in parts):
        raise ComparisonError("archive path traversal")
    current = repo
    for part in parts:
        current = current / part
        if current.is_symlink():
            raise ComparisonError("archive path contains symlink")
    resolved = current.resolve()
    if not resolved.is_relative_to(repo.resolve()):
        raise ComparisonError("archive path escapes repository")
    return resolved

def ref_file(repo: Path, ref: dict, label: str, limit: int = MAX_IMAGE) -> Path:
    if not isinstance(ref, dict) or not SHA.fullmatch(str(ref.get("sha256", ""))):
        raise ComparisonError(f"{label}: exact sha256 ref required")
    path = repo_file(repo, ref.get("path", ""))
    size, digest = stream_hash(path, limit)
    if size != ref.get("bytes") or digest != ref["sha256"]:
        raise ComparisonError(f"{label}: byte/hash drift")
    return path

def require_source_joins(source: dict, row: dict, label: str) -> None:
    for key in ("sourceHash", "tupleID", "tupleHash", "caseID", "caseHash", "recipeID", "runtimeCommit", "rendererHash", "recipeHash"):
        if row.get(key) != source.get(key):
            raise ComparisonError(f"{label}: source join mismatch {key}")

def validate_canonical_source_joins(source: dict, tuple_doc: dict, case_doc: dict, recipe_doc: dict) -> None:
    if tuple_doc.get("id") != source["tupleID"] or case_doc.get("id") != source["caseID"] or recipe_doc.get("id") != source["recipeID"]:
        raise ComparisonError("source tuple/case/recipe identity mismatch")
    if canonical_hash(tuple_doc) != source["tupleHash"]:
        raise ComparisonError("canonical tuple hash mismatch")
    if canonical_hash(case_doc) != source["caseHash"]:
        raise ComparisonError("canonical case hash mismatch")
    if canonical_hash(recipe_doc) != source["recipeHash"]:
        raise ComparisonError("canonical recipe hash mismatch")
    case_recipe = case_doc.get("recipe")
    if not isinstance(case_recipe, dict) or case_recipe.get("id") != recipe_doc.get("id") or case_recipe.get("hash") != source["recipeHash"]:
        raise ComparisonError("case recipe join mismatch")
    if case_doc.get("tuple") != tuple_doc:
        raise ComparisonError("case tuple join mismatch")

def load_pixels(path: Path):
    try:
        from PIL import Image
    except ImportError as exc:
        raise ComparisonError("Pillow is required by bounded reader") from exc
    try:
        with Image.open(path) as probe:
            width, height = probe.size
            if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
                raise ComparisonError("image pixel cap exceeded")
            if width * height * 4 > MAX_IMAGE:
                raise ComparisonError("decoded image cap exceeded")
            probe.verify()
        with Image.open(path) as image:
            image.load()
            return image.convert("RGBA")
    except ComparisonError:
        raise
    except Exception as exc:
        raise ComparisonError(f"image decode failed: {path}: {exc}") from exc

def image_geometry(image, row: dict, expected: dict, label: str) -> dict:
    width, height = image.size
    scale = row.get("observedScale")
    frame = row.get("framePx")
    if not isinstance(scale, (int, float)) or scale <= 0:
        raise ComparisonError(f"{label}: observedScale required")
    if not isinstance(frame, dict) or any(not isinstance(frame.get(k), (int, float)) for k in ("x", "y", "width", "height")):
        raise ComparisonError(f"{label}: framePx required")
    if frame["width"] <= 0 or frame["height"] <= 0:
        raise ComparisonError(f"{label}: invalid framePx")
    pixels = image.load(); red_count = 0; min_x = width; min_y = height; max_x = -1; max_y = -1; colors = Counter()
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if r >= 180 and r >= g * 1.5 and r >= b * 1.5 and a >= 200:
                red_count += 1; min_x = min(min_x, x); min_y = min(min_y, y); max_x = max(max_x, x); max_y = max(max_y, y)
                colors[(r, g, b, a)] += 1
                if len(colors) > 4096: raise ComparisonError(f"{label}: red color cardinality cap exceeded")
    if red_count == 0:
        raise ComparisonError(f"{label}: red paint absent")
    bbox = {"x": min_x, "y": min_y, "width": max_x - min_x + 1, "height": max_y - min_y + 1}
    dominant, count = colors.most_common(1)[0]
    expected_color = row.get("dominantRGBA")
    if not isinstance(expected_color, list) or len(expected_color) != 4 or dominant != tuple(expected_color):
        raise ComparisonError(f"{label}: dominant-red-color mismatch")
    return {"width": width, "height": height, "scale": scale, "framePx": frame, "redBbox": bbox, "dominantRed": dominant, "redPixels": red_count, "shapeDip": {"width": bbox["width"] / scale, "height": bbox["height"] / scale}}

def validate_platform_contract(manifest: dict, platform: str, row: dict, image, repo: Path, label: str) -> None:
    contract = manifest["expected"]["platforms"].get(platform)
    if not isinstance(contract, dict):
        raise ComparisonError(f"{label}: platform geometry contract missing")
    if [image.size[0], image.size[1]] != contract.get("imagePx"):
        raise ComparisonError(f"{label}: raw viewport pixels mismatch")
    for key in ("viewportPx", "framePx", "viewportDip"):
        if row.get(key) != contract.get(key):
            raise ComparisonError(f"{label}: measured {key} mismatch")
    for key in ("placement", "clip"):
        if row.get(key) != contract.get(key):
            raise ComparisonError(f"{label}: measured {key} mismatch")
    evidence = row.get("rawEvidence")
    if not isinstance(evidence, dict):
        raise ComparisonError(f"{label}: raw geometry/pixel evidence refs required")
    for key in ("geometryRef", "pixelsRef"):
        ref = evidence.get(key)
        path = ref_file(repo, ref, f"{label}.{key}", MAX_JSON)
        doc = bounded_json(path)
        if key == "geometryRef":
            for field in ("observedScale", "viewportPx", "framePx", "viewportDip", "placement", "clip", "sourceHash", "tupleID", "tupleHash", "caseID", "caseHash", "recipeID", "recipeHash"):
                if doc.get(field) != row.get(field):
                    raise ComparisonError(f"{label}: raw geometry join mismatch {field}")
        else:
            if doc.get("width") != image.size[0] or doc.get("height") != image.size[1] or doc.get("imageSha256") != row["image"].get("sha256") or any(doc.get(field) != row.get(field) for field in ("sourceHash", "tupleID", "tupleHash", "caseID", "caseHash", "recipeID", "recipeHash")):
                raise ComparisonError(f"{label}: raw pixel join mismatch")
    raw_refs = evidence.get("rawRefs")
    if not isinstance(raw_refs, list) or not raw_refs:
        raise ComparisonError(f"{label}: actual raw evidence refs required")
    for index, raw_ref in enumerate(raw_refs):
        raw_path = ref_file(repo, raw_ref, f"{label}.rawRefs[{index}]", MAX_JSON)
        bounded_json(raw_path)

def compare_manifest(manifest: dict, repo: Path) -> dict:
    if manifest.get("kind") != "factory-rectangle-pixel-pair-input-v1" or manifest.get("version") != 1:
        raise ComparisonError("input manifest kind/version mismatch")
    if str(repo) not in sys.path:
        sys.path.insert(0, str(repo))
    source = manifest.get("source")
    required = {"sourceHash", "tupleID", "tupleHash", "caseID", "caseHash", "runtimeCommit", "rendererHash", "recipeHash", "recipeID", "tupleRef", "caseRef", "recipeRef", "sourceRef"}
    if not isinstance(source, dict) or not required.issubset(source):
        raise ComparisonError("complete source/case/tuple join required")
    for key in ("sourceHash", "tupleHash", "caseHash", "rendererHash", "recipeHash"):
        if not SHA.fullmatch(str(source[key])):
            raise ComparisonError(f"source {key} must be exact sha256")
    tuple_path = ref_file(repo, source["tupleRef"], "source.tupleRef", MAX_JSON)
    case_path = ref_file(repo, source["caseRef"], "source.caseRef", MAX_JSON)
    recipe_path = ref_file(repo, source["recipeRef"], "source.recipeRef", MAX_JSON)
    ref_file(repo, source["sourceRef"], "source.sourceRef", MAX_SOURCE)
    tuple_doc = canonical_json(tuple_path); case_doc = canonical_json(case_path); recipe_doc = canonical_json(recipe_path)
    validate_canonical_source_joins(source, tuple_doc, case_doc, recipe_doc)
    if source["sourceRef"].get("sha256") != source["sourceHash"]:
        raise ComparisonError("source witness hash mismatch")
    expected = manifest.get("expected")
    if not isinstance(expected, dict) or expected.get("shapeDip") != {"width": 40, "height": 20} or expected.get("fillSemantic") != "system.red" or not isinstance(expected.get("platforms"), dict):
        raise ComparisonError("expected Rectangle geometry/color contract mismatch")
    rows = []
    for platform in ("mac", "windows"):
        batch = manifest.get(platform)
        if not isinstance(batch, dict) or batch.get("count") != 20 or not isinstance(batch.get("images"), list) or len(batch["images"]) != 20:
            raise ComparisonError(f"{platform}: exactly 20 image rows required")
        seen = set()
        for row in batch["images"]:
            run = row.get("run")
            if run in seen or not isinstance(run, int) or not 1 <= run <= 20:
                raise ComparisonError(f"{platform}: ordered distinct runs 1..20 required")
            seen.add(run); label = f"{platform}/run-{run:02d}"
            require_source_joins(source, row, label)
            path = ref_file(repo, row.get("image"), label)
            image = load_pixels(path)
            validate_platform_contract(manifest, platform, row, image, repo, label)
            geometry = image_geometry(image, row, expected, label)
            rows.append({"platform": platform, "run": run, "path": row["image"]["path"], "imageSha256": row["image"]["sha256"], "viewportDip": row["viewportDip"], "placement": row["placement"], "clip": row["clip"], "rawEvidence": row["rawEvidence"], **geometry})
        if seen != set(range(1, 21)):
            raise ComparisonError(f"{platform}: missing run")
    rows.sort(key=lambda item: (item["platform"], item["run"]))
    repeatability = {}
    for platform in ("mac", "windows"):
        own = [r for r in rows if r["platform"] == platform]
        hashes = {r["imageSha256"] for r in own}
        red_counts = [r["redPixels"] for r in own]
        bboxes = [r["redBbox"] for r in own]
        scales = [r["scale"] for r in own]
        colors = [r["dominantRed"] for r in own]
        repeatability[platform] = {
            "imageHashUniqueCount": len(hashes),
            "byteRepeatable": len(hashes) == 1,
            "redPixels": {"min": min(red_counts), "max": max(red_counts), "range": max(red_counts) - min(red_counts)},
            "redBboxStable": all(box == bboxes[0] for box in bboxes[1:]),
            "scaleStable": all(scale == scales[0] for scale in scales[1:]),
            "dominantColorStable": all(color == colors[0] for color in colors[1:]),
            "assessment": "byte-repeatable" if len(hashes) == 1 else "byte-varied-observation"
        }
    paired = []
    by_run = {(r["platform"], r["run"]): r for r in rows}
    for run in range(1, 21):
        mac = by_run[("mac", run)]; win = by_run[("windows", run)]
        paired.append({"run": run, "shapeDip": {"mac": mac["shapeDip"], "windows": win["shapeDip"], "equal": mac["shapeDip"] == win["shapeDip"]}, "viewportDip": {"mac": mac["viewportDip"], "windows": win["viewportDip"], "equal": mac["viewportDip"] == win["viewportDip"]}, "placement": {"mac": mac["placement"], "windows": win["placement"], "equal": mac["placement"] == win["placement"]}, "clipping": {"mac": mac["clip"], "windows": win["clip"], "equal": mac["clip"] == win["clip"]}})
    shape_equal = all(p["shapeDip"]["equal"] for p in paired)
    viewport_equal = all(p["viewportDip"]["equal"] for p in paired)
    placement_equal = all(p["placement"]["equal"] for p in paired)
    clipping_equal = all(p["clipping"]["equal"] for p in paired)
    mac_color = next(r for r in rows if r["platform"] == "mac")["dominantRed"]
    windows_color = next(r for r in rows if r["platform"] == "windows")["dominantRed"]
    rgb_equal = mac_color == windows_color
    geometry_equal = shape_equal and viewport_equal and placement_equal and clipping_equal
    return {"kind": "factory-rectangle-pixel-pair-comparison-v1", "status": "observed-diagnostic", "qualification": "held-until-independent-reader-review", "source": {k: source[k] for k in ("sourceHash", "tupleID", "tupleHash", "caseID", "caseHash", "recipeID", "runtimeCommit", "rendererHash", "recipeHash")}, "runs": rows, "repeatability": repeatability, "paired": paired, "semanticAgreement": {"fillSemantic": expected["fillSemantic"], "semanticLabelSource": "expected.fillSemantic", "semanticLabelEqual": True, "shapeDipEqual": shape_equal, "viewportDipEqual": viewport_equal, "placementEqual": placement_equal, "clippingEqual": clipping_equal, "rgbEqual": rgb_equal, "colorSemanticEqual": rgb_equal, "status": "observed" if geometry_equal else "mismatch", "strictStatus": "observed" if geometry_equal and rgb_equal else "mismatch"}, "colorByPlatform": {"mac": mac_color, "windows": windows_color}, "timingQualification": "held", "macAX": "not-used-for-paint-inference", "providerQualification": "held", "nativeActions": 0}

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--manifest", type=Path, required=True); ap.add_argument("--repo-root", type=Path, required=True); ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args(); result = {"kind": "factory-rectangle-pixel-pair-comparison-v1", "status": "held", "nativeActions": 0}
    try:
        result = compare_manifest(bounded_json(args.manifest), args.repo_root.resolve())
    except ComparisonError as exc:
        result.update({"status": "rejected", "reason": str(exc)})
        args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n"); print(json.dumps(result, sort_keys=True)); return 2
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n"); print(json.dumps(result, sort_keys=True)); return 0

if __name__ == "__main__":
    raise SystemExit(main())
