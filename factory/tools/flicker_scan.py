#!/usr/bin/env python3
"""Flicker scan for the H19 screen recordings (issue #15).

Reads the continuous screen recordings that job-interact.ps1 writes under SWIFTRIGHT_SCREEN_RECORD=1:
    <run>/windows/record-NN.mkv    ffv1, ffmpeg gdigrab of the whole virtual screen at 60 fps
    <run>/windows/record-NN.json   sidecar: host client rect, virtual screen, anchors, and each input step's start and end

For every recording it decodes each frame, crops the host client rect and reports, for each input step, the frames in
[step end, step end + window] (default 1000 ms):
  - black frames      every pixel of the host rect is (0,0,0)
  - black bands       runs of rows whose pixels are all (0,0,0) across the host rect (H19's notion; min run --min-band-rows)
  - transients        a run of frames that differs from the stable frame before it and from the stable frame after it
Recording-wide it also reports the achieved frame rate and dropped-frame gaps (intervals longer than 1.5 frame periods).
Sampling limit: frames are 16.7 ms apart at 60 fps, so a change shorter than one frame can never be seen.

Usage:
    python3 factory/tools/flicker_scan.py RUN_OR_WINDOWS_DIR [--out FILE] [--window-ms 1000] [--min-band-rows 1] [--stable-frames 1]
    python3 factory/tools/flicker_scan.py --selftest

Needs ffmpeg and ffprobe on PATH (ffmpeg >= 5.1 for -fps_mode) and Pillow (CI pins 11.3.0). Read-only on the recordings;
writes JSON to --out (default: flicker-scan.json inside the given directory). Prints one summary line.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops

SCHEMA = "flicker-scan/v1"
NOMINAL_FPS = 60.0
INPUT_EXCLUDE = {"wait", "dump", "shot"}   # steps that inject no input
EPOCH_SECONDS_MIN = 1e8                    # a pts above this is an absolute (UTC epoch) time, not relative to the ffmpeg start


def run_text(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def probe_video(path):
    """(width, height, [frame pts seconds]) of the first video stream."""
    info = json.loads(run_text(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                                "-of", "json", str(path)]))["streams"][0]
    pts_text = run_text(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "csv=p=0", str(path)])
    pts = []
    for line in pts_text.splitlines():
        token = line.strip().rstrip(",")
        if token and token != "N/A":
            pts.append(float(token))
    return int(info["width"]), int(info["height"]), pts


def iter_frames(path, width, height):
    """Yields every decoded frame as an RGB Pillow image, in order (ffmpeg rgb24 pipe, no frame duplication or drop)."""
    size = width * height * 3
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-map", "0:v:0", "-fps_mode", "passthrough",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    try:
        while True:
            buf = proc.stdout.read(size)
            if len(buf) < size:
                break
            yield Image.frombytes("RGB", (width, height), buf)
    finally:
        proc.stdout.close()
        rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"ffmpeg decode failed (exit {rc}) for {path}")


def crop_box(sidecar, width, height):
    """Host client rect in frame pixels. The sidecar's rect and virtual screen are physical pixels; a frame of a
    DPI-unaware grab is smaller, so the scale is frame width over virtual-screen width (checked on both axes)."""
    hc = sidecar.get("hostClient")
    vs = sidecar.get("virtualScreen")
    if not hc:
        return (0, 0, width, height)
    ox, oy, sx, sy = 0, 0, 1.0, 1.0
    if vs:
        ox, oy = vs[0], vs[1]
        sx, sy = width / float(vs[2]), height / float(vs[3])
        if abs(sx - sy) > 0.01:
            raise ValueError(f"frame {width}x{height} does not match the virtual screen {vs[2]}x{vs[3]} on both axes")
    left = round((hc[0] - ox) * sx)
    top = round((hc[1] - oy) * sy)
    right = round((hc[0] - ox + hc[2]) * sx)
    bottom = round((hc[1] - oy + hc[3]) * sy)
    left, top = max(0, left), max(0, top)
    right, bottom = min(width, right), min(height, bottom)
    if right - left < 2 or bottom - top < 2:
        raise ValueError(f"host rect {hc} is outside the frame {width}x{height} (virtual {vs})")
    return (left, top, right, bottom)


def black_row_runs(img):
    """Row runs (start, length) where every pixel is exactly (0,0,0). 'L' of the per-pixel channel maximum is 0 only for black."""
    w, h = img.size
    mx = ImageChops.lighter(ImageChops.lighter(img.getchannel(0), img.getchannel(1)), img.getchannel(2))
    if mx.getextrema()[0] > 0:          # no black pixel at all: no black row
        return []
    runs = []
    start = None
    for y in range(h):
        is_black = mx.crop((0, y, w, y + 1)).getextrema()[1] == 0
        if is_black and start is None:
            start = y
        elif not is_black and start is not None:
            runs.append((start, y - start))
            start = None
    if start is not None:
        runs.append((start, h - start))
    return runs


def features(timed_frames, box, min_band_rows):
    """Per-frame features from (time_seconds, image) pairs: digest of the host rect, full-black flag, band flag and longest band."""
    out = []
    for t, img in timed_frames:
        c = img.crop(box)
        digest = hashlib.sha256(c.tobytes()).hexdigest()
        runs = black_row_runs(c)
        longest = max((length for _, length in runs), default=0)
        out.append({"t": t, "digest": digest, "black": longest == c.size[1], "band": longest >= min_band_rows, "band_rows": longest,
                    "band_runs": len(runs)})
    return out


def plateaus(feats):
    """Consecutive identical frames merged. t1 is the start of the next plateau (None for the last one)."""
    out = []
    for i, f in enumerate(feats):
        if out and out[-1]["digest"] == f["digest"]:
            out[-1]["end"] = i
            continue
        out.append({"digest": f["digest"], "start": i, "end": i, "t0": f["t"], "black": f["black"], "band": f["band"], "band_rows": f["band_rows"]})
    for p in out:
        p["frames"] = p["end"] - p["start"] + 1
        p["t1"] = feats[p["end"] + 1]["t"] if p["end"] + 1 < len(feats) else None
        p["dur"] = (p["t1"] - p["t0"]) if p["t1"] is not None else None
    for k, p in enumerate(out):
        p["transient"] = 0 < k < len(out) - 1 and out[k - 1]["digest"] == out[k + 1]["digest"] \
            and out[k - 1]["frames"] >= STABLE[0] and out[k + 1]["frames"] >= STABLE[0]
    return out


STABLE = [1]   # a plateau counts as a stable frame when it lasts at least this many frames (--stable-frames)


def gaps(feats):
    period = 1.0 / NOMINAL_FPS
    out = []
    for i in range(1, len(feats)):
        dt = feats[i]["t"] - feats[i - 1]["t"]
        if dt > 1.5 * period:
            out.append({"atS": round(feats[i - 1]["t"] - feats[0]["t"], 4), "gapMs": round(dt * 1000, 1), "missingFrames": int(round(dt / period)) - 1})
    return out


def analyse(feats, steps, window_ms):
    """Per-step events in [step end, step end + window_ms] and recording-wide totals. steps: [{'step','op','end'}] with end in the frame time base."""
    plats = plateaus(feats)
    window = window_ms / 1000.0
    rec = {"frames": len(feats)}
    if len(feats) >= 2:
        span = feats[-1]["t"] - feats[0]["t"]
        rec["achievedFps"] = round((len(feats) - 1) / span, 2) if span > 0 else None
        rec["durationS"] = round(span, 3)
    rec["gaps"] = gaps(feats)
    rec["blackFrames"] = sum(1 for f in feats if f["black"])
    rec["bandFrames"] = sum(1 for f in feats if f["band"])
    rec["transients"] = sum(1 for p in plats if p["transient"])
    rec["plateaus"] = len(plats)
    per_step = []
    for s in steps:
        t0 = s["end"]
        t1 = t0 + window
        inwin = [f for f in feats if t0 <= f["t"] <= t1]
        events = []
        for p in plats:
            start = feats[p["start"]]["t"]
            if p["t1"] is not None and p["t1"] < t0:
                continue
            if start > t1:
                break
            if p["transient"] or p["black"] or p["band"]:
                events.append({"startMs": round((start - t0) * 1000, 1), "durationMs": None if p["dur"] is None else round(p["dur"] * 1000, 1),
                               "frames": p["frames"], "transient": p["transient"], "black": p["black"], "band": p["band"], "bandRows": p["band_rows"]})
        per_step.append({"step": s["step"], "op": s["op"], "endEpochS": round(t0, 4), "framesInWindow": len(inwin),
                         "blackFrameMs": [round((f["t"] - t0) * 1000, 1) for f in inwin if f["black"]],
                         "bandFrameMs": [round((f["t"] - t0) * 1000, 1) for f in inwin if f["band"]],
                         "events": events, "clean": not events})
    rec["steps"] = per_step
    return rec


def scan_recording(sidecar_path, window_ms, min_band_rows):
    side = json.loads(Path(sidecar_path).read_text(encoding="utf-8-sig"))
    mkv = sidecar_path.with_name(side.get("record") or sidecar_path.with_suffix(".mkv").name)
    if not mkv.is_file():
        raise FileNotFoundError(f"recording missing: {mkv}")
    width, height, pts = probe_video(mkv)
    if not pts:
        raise RuntimeError(f"no frames in {mkv}")
    anchor = float(side.get("anchorEpoch") or 0.0)
    absolute = pts[0] >= EPOCH_SECONDS_MIN
    times = [p if absolute else anchor + p for p in pts]
    box = crop_box(side, width, height)
    frames = []
    for i, img in enumerate(iter_frames(mkv, width, height)):
        if i >= len(times):
            raise RuntimeError(f"{mkv}: decoded more frames than ffprobe listed ({len(times)})")
        frames.append((times[i], img))
    if len(frames) != len(times):
        raise RuntimeError(f"{mkv}: decoded {len(frames)} frames, ffprobe listed {len(times)}")
    feats = features(frames, box, min_band_rows)
    steps = []
    for s in side.get("steps", []):
        if str(s.get("op")) in INPUT_EXCLUDE or s.get("epoch1") is None:
            continue
        steps.append({"step": s.get("step"), "op": s.get("op"), "end": float(s["epoch1"])})
    rec = analyse(feats, steps, window_ms)
    rec.update({"record": mkv.name, "run": side.get("run"), "width": width, "height": height, "hostCropPx": list(box),
                "ptsAbsolute": absolute, "ffmpegVersion": side.get("ffmpegVersion"), "ffmpegExitCode": side.get("ffmpegExitCode")})
    return rec


def summarise(recs, window_ms):
    if not recs:
        return "flicker-scan: no recordings"
    in_win = {"black": 0, "band": 0, "transient": 0, "steps": 0, "cleanSteps": 0}
    for r in recs:
        for s in r["steps"]:
            in_win["steps"] += 1
            in_win["cleanSteps"] += 1 if s["clean"] else 0
            in_win["black"] += len(s["blackFrameMs"])
            in_win["band"] += len(s["bandFrameMs"])
            in_win["transient"] += sum(1 for e in s["events"] if e["transient"])
    fps = [r["achievedFps"] for r in recs if r.get("achievedFps")]
    gap_n = sum(len(r["gaps"]) for r in recs)
    return (f"flicker-scan: {len(recs)} recording(s), {in_win['steps']} input step(s) scanned {window_ms} ms each: "
            f"{in_win['cleanSteps']} clean; black frames {in_win['black']}, band frames {in_win['band']}, transients {in_win['transient']}; "
            f"fps {min(fps) if fps else 'n/a'}-{max(fps) if fps else 'n/a'}, gaps {gap_n}")


def selftest():
    """Synthetic frames through the same feature and analysis code: no ffmpeg needed. Also ffmpeg round trip when ffmpeg exists."""
    W, H = 48, 36
    A = (200, 200, 200)

    def frame(color=A, band_rows=(), single_black_px=None, full_black=False):
        img = Image.new("RGB", (W, H), color)
        if full_black:
            img = Image.new("RGB", (W, H), (0, 0, 0))
        px = img.load()
        for y in band_rows:
            for x in range(W):
                px[x, y] = (0, 0, 0)
        if single_black_px is not None:
            px[single_black_px[0], single_black_px[1]] = (0, 0, 0)
        return img

    T0 = 100.0
    period = 1.0 / 60.0
    spec = {}
    for i in range(0, 181):
        if i == 30 or i == 31 or i == 32:
            spec[i] = frame(band_rows=(10, 11, 12))
        elif i == 35:
            spec[i] = frame(single_black_px=(5, 20))
        elif i in (40, 41):
            spec[i] = frame(full_black=True)
        elif i in (50, 51):
            spec[i] = frame(color=(90, 90, 200))
        elif i in (120, 121):
            spec[i] = frame(color=(10, 150, 10))
        else:
            spec[i] = frame()
    timed = []
    for i in range(0, 181):
        t = T0 + i * period + (period if i >= 130 else 0.0)   # one frame skipped at 130: a gap
        timed.append((t, spec[i]))
    box = (0, 0, W, H)
    feats = features(timed, box, 1)
    steps = [{"step": 1, "op": "click", "end": T0 + 30 * period}, {"step": 2, "op": "key", "end": T0 + 122 * period + 0.3 * period}]
    # Step 1 window [T0+0.5, T0+1.5]: band 30-32, pixel-only 35, black 40-41, colour 50-51. Step 2 window starts after the 120-121 change.
    rec = analyse(feats, steps, 1000)
    s1, s2 = rec["steps"]
    checks = []

    def check(name, cond):
        checks.append((name, bool(cond)))

    check("black frames in step 1 window = 2", len(s1["blackFrameMs"]) == 2)
    check("band frames in step 1 window = 5 (30,31,32,40,41)", len(s1["bandFrameMs"]) == 5)
    transients1 = [e for e in s1["events"] if e["transient"]]
    check("transients in step 1 window = 4", len(transients1) == 4)
    check("band transient 30-32 is 3 frames and a band", any(e["band"] and e["frames"] == 3 and not e["black"] for e in transients1))
    check("pixel-only change at 35 is not a band", any(e["frames"] == 1 and not e["band"] and not e["black"] for e in transients1))
    check("full black 40-41 is black and a band", any(e["black"] and e["band"] and e["frames"] == 2 for e in transients1))
    check("colour change 50-51 is a transient and not black", any(e["frames"] == 2 and not e["black"] and not e["band"] for e in transients1))
    check("step 2 window clean (120-121 lies before it)", s2["clean"] and len(s2["blackFrameMs"]) == 0)
    check("recording-wide transients = 5 (the 120-121 change counts here)", rec["transients"] == 5)
    check("one dropped-frame gap at frame 130", len(rec["gaps"]) == 1 and rec["gaps"][0]["missingFrames"] == 1)
    check("band rows of a single black pixel are not counted", features([(0.0, frame(single_black_px=(0, 0)))], box, 1)[0]["band_rows"] == 0)
    check("black band rows exact (rows 10-12 = 3)", features([(0.0, frame(band_rows=(10, 11, 12)))], box, 1)[0]["band_rows"] == 3)
    check("transient ends are timed in ms from the step end", abs(transients1[0]["startMs"]) < 1.0)
    check("host crop is the frame when no sidecar rect", crop_box({}, W, H) == (0, 0, W, H))
    check("host crop scales a DPI-unaware frame", crop_box({"hostClient": [200, 100, 400, 300], "virtualScreen": [0, 0, 1024, 768]}, 512, 384) == (100, 50, 300, 200))
    if shutil.which("ffmpeg") and shutil.which("ffprobe"):
        with tempfile.TemporaryDirectory(prefix="flicker-selftest-") as tmp:
            mkv = Path(tmp) / "record-01.mkv"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c=0x{'c8'*3}:s={W}x{H}:r=60:d=0.5",
                            "-c:v", "ffv1", "-level", "3", str(mkv)], check=True)
            w, h, pts = probe_video(mkv)
            n = sum(1 for _ in iter_frames(mkv, w, h))
            check("ffmpeg round trip: decoded frames = probed frames (30)", n == len(pts) == 30 and (w, h) == (W, H))
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(("ok   " if ok else "FAIL ") + name)
    if failed:
        print(f"selftest FAILED: {len(failed)} check(s)")
        return 1
    print(f"selftest ok: {len(checks)} checks")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description="Scan H19 screen recordings for black frames, black bands and transients around input steps.")
    ap.add_argument("path", nargs="?", help="run directory or windows directory holding record-NN.json sidecars")
    ap.add_argument("--out", help="JSON output (default: flicker-scan.json inside the directory)")
    ap.add_argument("--window-ms", type=int, default=1000, help="window after each input step (ms, default 1000)")
    ap.add_argument("--min-band-rows", type=int, default=1, help="shortest run of all-black rows that counts as a band (default 1)")
    ap.add_argument("--stable-frames", type=int, default=1, help="frames a plateau must last to count as the stable frame around a transient (default 1)")
    ap.add_argument("--selftest", action="store_true", help="run the synthetic self-test and exit")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.path:
        ap.error("path is required unless --selftest")
    STABLE[0] = max(1, a.stable_frames)
    root = Path(a.path).resolve()
    sidecars = sorted(p for p in root.rglob("record-*.json") if p.is_file())
    if not sidecars:
        print(f"flicker-scan: no record-*.json under {root}", file=sys.stderr)
        return 2
    recs = []
    errors = []
    for sp in sidecars:
        try:
            r = scan_recording(sp, a.window_ms, a.min_band_rows)
            r["sidecar"] = str(sp.relative_to(root))
            recs.append(r)
        except (RuntimeError, ValueError, FileNotFoundError, subprocess.CalledProcessError, KeyError, json.JSONDecodeError) as e:
            errors.append({"sidecar": str(sp.relative_to(root)), "error": str(e)})
    doc = {"schema": SCHEMA, "root": str(root), "windowMs": a.window_ms, "minBandRows": a.min_band_rows, "stableFrames": STABLE[0],
           "samplingIntervalMs": round(1000.0 / NOMINAL_FPS, 3), "recordings": recs, "errors": errors, "summary": summarise(recs, a.window_ms)}
    out = Path(a.out) if a.out else (root / "flicker-scan.json" if root.is_dir() else root.parent / "flicker-scan.json")
    out.write_text(json.dumps(doc, indent=1), encoding="utf-8")
    print(doc["summary"] + (f"; {len(errors)} recording(s) failed, see errors" if errors else "") + f"; wrote {out}")
    return 1 if errors and not recs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
