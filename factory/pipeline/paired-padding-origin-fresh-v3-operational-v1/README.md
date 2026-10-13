# Paired padding origin fresh operational v3

This packet adds an independent frozen-input guard before any workflow collection. It verifies `source-pins.json` itself plus all 69 pinned fresh source/run blobs, then verifies cleanup-rehydration-v2 plan/helper bytes before rehydration. Production workflow collection receives rehydrated `origin_reader` and archive `artifact_reader`; no installed fallback is used.

Replay result: 20 Mac captures, 180 origin descriptors verified, zero Windows typed captures, parity/pixel/timing/promotion held. Rehydration used 423 mappings and removed PID-owned internal temp data. Native/compiler executions: zero.

Controls mutate only temporary copies and all reject: source-pin manifest schema, pinned run capture digest, and tool-cache bytes against expected digest. Frozen v2 operational packet remains unchanged.
