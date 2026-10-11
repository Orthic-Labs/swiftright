Strict offline foundational timing consumer; existing comparator, schemas, reports, spikes, renderer & ABI remain unchanged. `consumer.py` validates exact UTF8 raw input closure against externally frozen expected byte pins: case, acceptance policy, context, bounds & each capture. It recomputes case/tuple identity, joins protected policy hashes & bound values, then reconstructs per-run duration, interruption incoming/outgoing velocities & presentation stalls including stimulus→first-frame & last-frame→completion gaps. Dropped frames remain raw evidence but do not shorten presentation stalls.

New `timing-observations-v1` records require explicit monotonic clock ID & nanosecond unit on every event/sample/frame. Events require stimulus≤transaction≤interruption≤completion. Samples start after transaction; frames stay within stimulus/completion. All timestamp sequences are strict & interruption has exact sample plus incoming/outgoing brackets. Velocity uses only adjacent slopes touching interruption; unrelated global peak cannot substitute. Protected context fixes animation identities & scenario. Unknown clock domain/unit declarations or missing channels stay held; invalid explicit clock joins reject. Declared static scenarios yield not-applicable, never timing pass. Legacy v0.1 shared `meta.clock` alone stays held.

`report_join.py` reconstructs raw evidence, bound/context/result hashes, actual derived bytes & supplied verdict before reporting observational status. Gate callback returns blocked plus bound observational details; this foundational reconstruction never establishes native parity or invents clock qualification. Actual native channel qualification remains separate evidence.

`retention.py` writes exact raw bytes & derived details to immutable hash-named artifacts, verifies existing bytes before reuse & checks hashes/sizes on retrieval. `proof.json` retains baseline raw strings, protected expected pins, complete derived artifact, 22 changed-byte controls & six forged report joins. Faults start from accepted baseline; coherent raw mutations use recomputed capture pins to reach semantic gates. Sole raw-hash fault deliberately preserves expected source pin. Tests also cover retention tampering, static/missing channels, legacy clocks & gate rejection.

Replay:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/comparison/timing-consumer-v1/test_consumer.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/comparison/timing-consumer-v1/build_packet.py --check
```

All evidence is explicitly synthetic/unit-evidence; no native timing run occurred. New source, meaningful controls, immutable artifacts & exact replay are complete.
