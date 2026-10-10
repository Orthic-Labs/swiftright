"""Parse exact integers/rationals; assess observations without widening brackets."""
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import sys

def integer(value):
    if type(value) is not int:
        raise ValueError('native integer required')
    return value

def analyze(rows):
    metadata = rows[0]
    if metadata['kind'] != 'metadata':
        raise ValueError('metadata must precede samples')
    tick_ns = Fraction(integer(metadata['machTimebase']['numer']), integer(metadata['machTimebase']['denom']))
    if tick_ns <= 0:
        raise ValueError('positive native timebase required')
    reads = [row for row in rows[1:] if row['kind'] == 'host-read']
    trips = [row for row in rows[1:] if row['kind'] == 'round-trip']
    if len(reads) != metadata['hostReads'] or len(trips) != metadata['roundTrips'] or len(rows) != 1 + len(reads) + len(trips):
        raise ValueError('complete native row counts required')
    misses = []
    floor_conversion_failures = []
    make_floor_failures = []
    residuals = Counter()
    deltas = Counter()
    rational_inside = 0
    ceiling_inside = 0
    ceiling_roundtrips = 0
    rational_misses = []
    for group in [reads, trips]:
        if [integer(row['index']) for row in group] != list(range(len(group))):
            raise ValueError('complete ordered native indexes required')
        for row in group:
            t = row['hostTime']
            scale = integer(t['timescale'])
            flags = integer(t['flags'])
            if scale <= 0 or flags & 1 == 0 or flags & ~3 or integer(t['epoch']) != 0:
                raise ValueError('valid finite epoch-zero native CMTime required')
            value = integer(t['value'])
            ns = Fraction(value * 1000000000, scale)
            converted = integer(row['convertedSystemTicks'])
            inverse_ceiling_ticks = -((-ns) // tick_ns)
            if converted != ns // tick_ns:
                floor_conversion_failures.append({'kind': row['kind'], 'index': row['index']})
            if row['kind'] == 'host-read':
                before = integer(row['machBefore']); after = integer(row['machAfter'])
                if before > after:
                    raise ValueError('mach bracket reversed')
                rational_inside += before * tick_ns <= ns <= after * tick_ns
                ceiling_inside += before <= inverse_ceiling_ticks <= after
                if not before * tick_ns <= ns <= after * tick_ns:
                    rational_misses.append({'index': row['index'], 'representedTimeMinusBeforeNs': str(ns - before * tick_ns),
                                            'representedTimeMinusAfterNs': str(ns - after * tick_ns),
                                            'inverseCeilingTicks': inverse_ceiling_ticks,
                                            'inverseCeilingWithinBracket': before <= inverse_ceiling_ticks <= after})
                if not before <= converted <= after:
                    misses.append({'index': row['index'], 'belowBeforeTicks': before - converted,
                                   'aboveAfterTicks': converted - after,
                                   'representedTimeMinusBeforeNs': str(ns - before * tick_ns),
                                   'raw': row})
            else:
                original = integer(row['inputSystemTicks'])
                ceiling_roundtrips += inverse_ceiling_ticks == original
                deltas[str(converted - original)] += 1
                residuals[str(ns - original * tick_ns)] += 1
                if value != (original * tick_ns * scale) // 1000000000:
                    make_floor_failures.append(row['index'])
    return {'hostReads': len(reads), 'roundTrips': len(trips), 'tickNs': str(tick_ns),
            'strictBrackets': len(reads) - len(misses), 'strictBracketMisses': misses,
            'exactRationalCMTimeWithinMachBracket': rational_inside,
            'exactRationalCMTimeOutsideMachBracket': len(reads) - rational_inside,
            'exactRationalBracketMisses': rational_misses,
            'observedMakeFloorInverseCeilingWithinMachBracket': ceiling_inside,
            'observedMakeFloorInverseCeilingOutsideMachBracket': len(reads) - ceiling_inside,
            'observedMakeFloorInverseCeilingRoundTripMatches': ceiling_roundtrips,
            'observedMakeFloorInverseCeilingRoundTripMismatches': len(trips) - ceiling_roundtrips,
            'roundTripDeltaTicks': dict(deltas), 'makeHostResidualNs': dict(residuals),
            'floorScaleConversionModelFailures': floor_conversion_failures,
            'makeHostFloorCMTimeModelFailures': make_floor_failures,
            'interpretation': 'Floor-scale models are tested observations on these bytes, not documented universal error guarantees. Original timing controls retain exact strict results.'}

def validate_candidate(result):
    """Candidate interpretation guard; preserves strict misses, never accepts altered bytes silently."""
    if (result['floorScaleConversionModelFailures'] or result['makeHostFloorCMTimeModelFailures']
            or result['observedMakeFloorInverseCeilingRoundTripMismatches']
            or result['observedMakeFloorInverseCeilingOutsideMachBracket']):
        raise ValueError('observational floor/inverse candidate contradicted by raw evidence')

def main(path):
    path = Path(path)
    raw = path / 'raw.jsonl'
    result = analyze([json.loads(line) for line in raw.read_text().splitlines()])
    result.update({'kind': 'headless-host-clock-calibration-analysis',
                   'rawHash': 'sha256:' + hashlib.sha256(raw.read_bytes()).hexdigest(),
                   'analyzerHash': 'sha256:' + hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    (path / 'analysis.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'strictBracketMisses'}))

if __name__ == '__main__':
    main(sys.argv[1])
