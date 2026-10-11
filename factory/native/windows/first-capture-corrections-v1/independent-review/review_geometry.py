"""Independent source-contract arithmetic, not compiled Swift or native execution."""
import math
import struct
import json

def f32(value):
    return struct.unpack('f', struct.pack('f', value))[0]

def swift_round(value):
    return math.copysign(math.floor(abs(value) + 0.5), value)

def snap_extent(origin, extent):
    return swift_round(origin + extent) - swift_round(origin)

def main():
    controls = []
    d, x = 159.4, 0.4
    actual = snap_extent(x, d)
    assert actual == 160 and swift_round(d) == 159
    controls.append(dict(name='fractional-origin', measured=d, origin=x,
                         snapped=actual, oldRoundedExtent=swift_round(d)))
    d, x = 159.0, -0.5
    actual = snap_extent(x, d)
    assert actual == 160 and math.floor(d) == math.ceil(d) == 159
    controls.append(dict(name='signed-half-tie', measured=d, origin=x,
                         snapped=actual, rawFloor=math.floor(d), rawCeil=math.ceil(d)))
    raw, scale, x = f32(159), f32(1.25), 0.500002
    logical = f32(raw / scale)
    physical = float(logical) * float(scale)
    actual = snap_extent(x, physical)
    assert physical == 158.99999618530273 and actual == 158
    controls.append(dict(name='runtime-float-conversion', measured=raw, scale=scale,
                         logical=logical, reconstructedPhysical=physical,
                         origin=x, snapped=actual))
    # Sweep positive/negative origins & exact half ties independently of host case.
    tested = 0
    for d in (0., 0.1, 0.5, 1., 1.5, 2., 159., 159.4, 159.6):
        for x in (-160.5, -159.5, -1.5, -0.5, -0.49, 0., 0.4, 0.5, 1.5):
            n = snap_extent(x, d)
            admissible = n in (math.floor(d), math.ceil(d)) or (
                d >= 1 and d == math.floor(d) and n == d + 1 and
                swift_round(x) < 0 and swift_round(x) + n > 0)
            assert admissible, (x, d, n)
            tested += 1
    print(json.dumps(dict(kind='independent-source-arithmetic', nativeExecution=0,
                          compilerExecution=0, controls=controls, sweepCases=tested), indent=2))

if __name__ == '__main__':
    main()
