"""SwiftUI built-in spring model fitted in the R3 spike (see SPIKE-RESULT.md). Usage: python3 model.py samples.jsonl  (prints max error per spring and cadence)."""
import json, math, cmath, sys

H = 1 / 300  # SwiftUI steps a built-in spring at 300 Hz


def params(name):
    """(stiffness k, damping c) for unit mass, from the Animation the sampler used."""
    if name in ("default", "smooth"): d, b = 0.5, 0.0
    elif name == "snappy": d, b = 0.5, 0.15
    elif name == "bouncy": d, b = 0.5, 0.3
    elif name.startswith("spring(duration"):
        a = name[len("spring(duration:"):-1].split(",bounce:"); d, b = float(a[0]), float(a[1])
    elif name.startswith("spring(response"):
        a = name[len("spring(response:"):-1].split(",dampingFraction:"); w = 2 * math.pi / float(a[0]); return w * w, 2 * float(a[1]) * w
    elif name.startswith("interpolatingSpring"): return 170.0, 15.0
    w = 2 * math.pi / d
    z = 1 - b if b >= 0 else 1 / (1 + b)
    return w * w, 2 * z * w


def integrated(k, c, times):
    """Semi-implicit Euler at H; a call at time t has taken every step whose end is strictly before t."""
    x = v = acc = 0.0; out = []
    for t in times:
        while acc + H < t:
            v += (k * (1 - x) - c * v) * H; x += v * H; acc += H
        out.append(x)
    return out


def closed(k, c, t):
    """interpolatingSpring: the analytic damped oscillator from rest at 0 toward 1."""
    d = c * c - 4 * k; r1 = (-c + cmath.sqrt(d)) / 2; r2 = (-c - cmath.sqrt(d)) / 2
    return 1 - ((r2 * cmath.exp(r1 * t) - r1 * cmath.exp(r2 * t)) / (r2 - r1)).real


if __name__ == "__main__":
    for line in open(sys.argv[1]):
        r = json.loads(line); vals = [v for v in r["v"] if v is not None]
        times = []; t = 0.0
        for _ in vals: times.append(t); t += r["step"]   # the sampler accumulates t += step
        k, c = params(r["name"])
        model = [closed(k, c, t) for t in times] if r["name"].startswith("interpolating") else integrated(k, c, times)
        print("%-46s step=%-8s maxerr=%.1e" % (r["name"], r["step"], max(abs(a - b) for a, b in zip(model, vals))))
