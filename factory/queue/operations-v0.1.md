# Queue operations protocol v0.1

This package supplies local, staged queue mechanics. State is explicitly `mode: unit` and activation remains held until plan round 3 exits. Every generated queue receipt carries `synthetic: true`; these receipts cannot establish parity or release production queue access.

`QueueStore(file, registry_file=...)` uses an advisory lock and same-directory atomic replacement. A trusted registry file is required for enqueue and claim. Ticket-provided dependency or progress fields are never consulted. A block is eligible when each semantic dependency is registry `parity`, or both blocks declare the same non-empty `bootstrapGroup`. Missing dependencies block.

`enqueue(ticket_or_block_id, report_link=None)` creates an immutable ticket. `claim(ticket_id, owner, ttl_seconds=3600)` assigns one live owner; an occupied claim produces a conflict receipt without replacing existing ownership. Competing tickets for one block cannot be claimed concurrently. `renew(ticket_id, owner, ttl_seconds=3600)` is limited to current live owner. `expire(ticket_id=None)` records each expiry before making its ticket reclaimable; next claim includes a receipt-backed reclaim record. `close(ticket_id, gate_receipt)` requires a configured trusted verifier that proves a passing gate receipt binds exact ticket & block. Local status fields alone never prove a gate.

`add_waiver(waiver, block=...)` accepts only when a configured trusted maintainer signature verifier approves it. Scope names one block & one dependency, and waiver expires. Waiver can satisfy queue eligibility for that scoped dependency only; it never changes registry progress or grants parity. The shipped CLI has no trusted signature or gate verifier, so it cannot add waivers or close tickets.

The CLI is `python -m factory.queue`. It supports `list`, `enqueue`, `claim`, `renew`, `expire`, and `show`; it cannot activate production mode. Operation receipts follow `schemas/receipt.schema.json`, ticket records follow `schemas/ticket.schema.json`, and signed waiver inputs follow `schemas/waiver.schema.json`.
