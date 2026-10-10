"""Atomic local queue operations with trusted-registry prerequisite checks."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import tempfile
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterator

from factory.tools import canonical_json


class QueueError(RuntimeError):
    """Base queue error."""


class BlockedError(QueueError):
    """An operation is held by a prerequisite or staged-mode boundary."""


class ConflictError(QueueError):
    """A competing owner or immutable-ID conflict was detected."""


class InvalidOperation(QueueError):
    """An operation does not satisfy queue protocol invariants."""


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _stamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _parse_time(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as exc:
        raise InvalidOperation(f"invalid RFC3339 timestamp: {value!r}") from exc
    if parsed.tzinfo is None:
        raise InvalidOperation("timestamps must include a timezone")
    return parsed.astimezone(timezone.utc)


def _hash(value: Any) -> str:
    return canonical_json.sha256(value)


def _file_hash(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def _load_json(path: Path) -> Any:
    try:
        return canonical_json.load(path)
    except (OSError, canonical_json.CanonicalJSONError) as exc:
        raise InvalidOperation(f"cannot read strict JSON from {path}: {exc}") from exc


class QueueStore:
    """Single-file queue database guarded by an advisory process lock.

    Args:
        file: queue database path; absent files are initialized in held unit mode.
        registry_file: trusted block-registry document. Ticket dependency claims
            are ignored; dependencies and bootstrap groups come from this file.
        clock: injectable UTC clock for deterministic local tests.
        waiver_verifier: trusted signature verifier. It receives waiver object and
            must return True; caller-supplied booleans are never treated as proof.
        gate_verifier: trusted gate verifier. It receives receipt object and must
            return validated binding data with ticketId, block, operation='gate',
            status='pass', and trusted=True. Without it, ticket close is blocked.
    """

    PROTOCOL_VERSION = "0.1"
    MODE = "unit"
    ACTIVATION = "held-until-plan-round-3-exit"

    def __init__(
        self,
        file: str | Path,
        registry_file: str | Path | None = None,
        *,
        clock: Callable[[], datetime] = _utcnow,
        waiver_verifier: Callable[[dict[str, Any]], bool] | None = None,
        gate_verifier: Callable[[dict[str, Any]], dict[str, Any] | bool] | None = None,
    ) -> None:
        self.path = Path(file)
        self.lock_path = self.path.with_name(self.path.name + ".lock")
        self.registry_path = Path(registry_file) if registry_file is not None else None
        self.clock = clock
        self.waiver_verifier = waiver_verifier
        self.gate_verifier = gate_verifier
        self._thread_lock = threading.RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._locked():
            if not self.path.exists():
                self._write(self._empty_state())
            else:
                self._read_state()

    @classmethod
    def _empty_state(cls) -> dict[str, Any]:
        return {
            "kind": "queue-state",
            "version": cls.PROTOCOL_VERSION,
            "mode": cls.MODE,
            "activation": cls.ACTIVATION,
            "tickets": {},
            "receipts": {},
            "waivers": {},
        }

    @contextmanager
    def _locked(self) -> Iterator[None]:
        with self._thread_lock:
            self.lock_path.parent.mkdir(parents=True, exist_ok=True)
            with self.lock_path.open("a+b") as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _read_state(self) -> dict[str, Any]:
        state = _load_json(self.path)
        if not isinstance(state, dict) or state.get("kind") != "queue-state":
            raise InvalidOperation("queue file has invalid root envelope")
        if state.get("version") != self.PROTOCOL_VERSION:
            raise InvalidOperation("unsupported queue state version")
        if state.get("mode") != self.MODE or state.get("activation") != self.ACTIVATION:
            raise InvalidOperation("queue state activation boundary was modified")
        for key in ("tickets", "receipts", "waivers"):
            if not isinstance(state.get(key), dict):
                raise InvalidOperation(f"queue state {key} must be an object")
        return state

    def _write(self, state: dict[str, Any]) -> None:
        data = canonical_json.dump_bytes(state) + b"\n"
        fd, temp_name = tempfile.mkstemp(prefix=f".{self.path.name}.", dir=self.path.parent)
        try:
            with os.fdopen(fd, "wb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temp_name, self.path)
            dir_fd = os.open(self.path.parent, os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)

    def _registry(self) -> tuple[dict[str, Any], str]:
        if self.registry_path is None:
            raise BlockedError("trusted registry_file is required for queue eligibility")
        registry = _load_json(self.registry_path)
        if not isinstance(registry, dict) or registry.get("kind") != "block-registry":
            raise InvalidOperation("trusted registry has invalid kind")
        blocks = registry.get("blocks")
        if not isinstance(blocks, list):
            raise InvalidOperation("trusted registry has no block list")
        return registry, _file_hash(self.registry_path)

    @staticmethod
    def _registry_blocks(registry: dict[str, Any]) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {}
        for block in registry["blocks"]:
            if not isinstance(block, dict) or not isinstance(block.get("id"), str):
                raise InvalidOperation("registry contains malformed block entry")
            if block["id"] in result:
                raise InvalidOperation(f"duplicate registry block {block['id']!r}")
            result[block["id"]] = block
        return result

    def _receipt(
        self,
        state: dict[str, Any],
        operation: str,
        status: str,
        *,
        inputs: list[dict[str, str]] | None = None,
        details: dict[str, Any] | None = None,
        at: datetime | None = None,
    ) -> dict[str, Any]:
        when = at or self.clock()
        receipt_id = f"queue/{uuid.uuid4().hex}"
        body: dict[str, Any] = {
            "kind": "queue-receipt",
            "version": self.PROTOCOL_VERSION,
            "id": receipt_id,
            "operation": operation,
            "status": status,
            "mode": "unit",
            "synthetic": True,
            "startedAt": _stamp(when),
            "finishedAt": _stamp(when),
            "inputs": inputs or [],
            "outputs": [],
            "details": details or {},
        }
        body["provenance"] = {
            "sourceHash": _hash({"operation": operation, "details": details or {}, "at": _stamp(when)}),
            "createdAt": _stamp(when),
            "producer": "factory.queue.unit",
        }
        body["hash"] = _hash(body)
        state["receipts"][receipt_id] = body
        return body

    def _dependency_data(
        self, block_id: str, registry: dict[str, Any], registry_hash: str
    ) -> tuple[dict[str, Any], list[str], str | None]:
        blocks = self._registry_blocks(registry)
        block = blocks.get(block_id)
        if block is None:
            raise InvalidOperation(f"block {block_id!r} is absent from trusted registry")
        deps = block.get("semanticDependencies", [])
        group = block.get("bootstrapGroup")
        if not isinstance(deps, list) or any(not isinstance(dep, str) for dep in deps):
            raise InvalidOperation(f"registry dependencies for {block_id!r} are malformed")
        # All prerequisite decisions below use this freshly read trusted registry.
        return block, deps, group if isinstance(group, str) else None

    def _eligible(
        self,
        block_id: str,
        block: dict[str, Any],
        dependencies: list[str],
        group: str | None,
        blocks: dict[str, dict[str, Any]],
        state: dict[str, Any],
        now: datetime,
    ) -> list[str]:
        blocked: list[str] = []
        for dependency in dependencies:
            dep = blocks.get(dependency)
            if dep is None:
                blocked.append(f"missing:{dependency}")
                continue
            if dep.get("progress") == "parity":
                continue
            dep_group = dep.get("bootstrapGroup")
            if group and dep_group == group:
                continue
            waived = False
            for waiver in state["waivers"].values():
                scope = waiver.get("scope", {})
                if (
                    waiver.get("block") == block_id
                    and scope.get("dependency") == dependency
                    and waiver.get("verified") is True
                    and _parse_time(waiver["expiresAt"]) > now
                ):
                    waived = True
                    break
            if not waived:
                blocked.append(dependency)
        return blocked

    def add_waiver(self, waiver: dict[str, Any], *, block: str) -> dict[str, Any]:
        """Store a maintainer-signed, exact dependency waiver after verification."""
        if self.waiver_verifier is None or not self.waiver_verifier(waiver):
            raise BlockedError("waiver requires a configured trusted maintainer signature verifier")
        if waiver.get("kind") != "waiver" or waiver.get("version") != self.PROTOCOL_VERSION:
            raise InvalidOperation("waiver must use schema protocol v0.1")
        scope = waiver.get("scope")
        if (
            not isinstance(scope, dict)
            or scope.get("block") != block
            or not isinstance(scope.get("dependency"), str)
        ):
            raise InvalidOperation("queue waiver scope must name one dependency")
        if not waiver.get("maintainer") or not waiver.get("reason") or not waiver.get("evidence"):
            raise InvalidOperation("waiver requires maintainer, reason, and evidence")
        now = self.clock()
        if _parse_time(waiver.get("expiresAt", "")) <= now:
            raise InvalidOperation("waiver is expired")
        with self._locked():
            state = self._read_state()
            waiver_id = waiver.get("id")
            if not isinstance(waiver_id, str) or not waiver_id:
                raise InvalidOperation("waiver id is required")
            existing = state["waivers"].get(waiver_id)
            verified_record = {**waiver, "block": block, "verified": True}
            if existing is not None and existing != verified_record:
                raise ConflictError("waiver ID already exists with different content")
            state["waivers"][waiver_id] = verified_record
            self._receipt(state, "waiver", "pass", details={"waiverId": waiver_id, "block": block}, at=now)
            self._write(state)
            return verified_record

    def enqueue(self, ticket: dict[str, Any] | str, *, report_link: str | None = None) -> dict[str, Any]:
        """Create a ticket from trusted registry data; submitted deps are not trusted."""
        if isinstance(ticket, str):
            ticket_id, block_id, source = f"ticket/{ticket}", ticket, {"block": ticket}
        elif isinstance(ticket, dict):
            block_id = ticket.get("block")
            ticket_id = ticket.get("id")
            source = ticket
        else:
            raise InvalidOperation("enqueue expects block ID or ticket object")
        if not isinstance(block_id, str) or not isinstance(ticket_id, str):
            raise InvalidOperation("ticket requires string id and block")
        registry, registry_hash = self._registry()
        block, dependencies, group = self._dependency_data(block_id, registry, registry_hash)
        blocks = self._registry_blocks(registry)
        now = self.clock()
        with self._locked():
            state = self._read_state()
            blocked = self._eligible(block_id, block, dependencies, group, blocks, state, now)
            if blocked:
                receipt = self._receipt(state, "enqueue", "blocked", inputs=[{"id": "registry", "hash": registry_hash}], details={"block": block_id, "blockedDependencies": blocked}, at=now)
                self._write(state)
                raise BlockedError(f"dependencies not eligible for {block_id}: {', '.join(blocked)} (receipt {receipt['id']})")
            # Existing IDs are immutable. Even an identical retry returns existing record.
            existing = state["tickets"].get(ticket_id)
            if existing:
                if existing.get("block") == block_id:
                    return existing
                raise ConflictError(f"ticket ID {ticket_id!r} already belongs to another block")
            ticket_hash = _hash(source)
            dependencies_refs = [
                {"id": f"block/{dep}", "hash": _hash(blocks[dep])}
                for dep in dependencies if dep in blocks
            ]
            record: dict[str, Any] = {
                "kind": "ticket",
                "version": self.PROTOCOL_VERSION,
                "id": ticket_id,
                "block": block_id,
                "dependencies": dependencies_refs,
                "status": "open",
                "openedAt": _stamp(now),
                "provenance": {
                    "sourceHash": ticket_hash,
                    "createdAt": _stamp(now),
                    "producer": "factory.queue.unit",
                    "inputs": [{"id": "block-registry", "hash": registry_hash}],
                },
                "unit": True,
            }
            if group:
                record["bootstrapGroup"] = group
            for field in ("recipe", "cases", "failingVerdicts"):
                if field not in source:
                    continue
                refs = source[field] if isinstance(source[field], list) else [source[field]]
                if field == "recipe" and len(refs) != 1:
                    raise InvalidOperation("recipe must be one hash reference")
                for ref in refs:
                    if (
                        not isinstance(ref, dict)
                        or not isinstance(ref.get("id"), str)
                        or not isinstance(ref.get("hash"), str)
                        or not ref["hash"].startswith("sha256:")
                        or len(ref["hash"]) != 71
                    ):
                        raise InvalidOperation(f"{field} must contain artifact hash references")
                record[field] = refs[0] if field == "recipe" else refs
            if report_link:
                record["reportLink"] = report_link
            state["tickets"][ticket_id] = record
            self._receipt(state, "enqueue", "pass", inputs=[{"id": "block-registry", "hash": registry_hash}], details={"ticketId": ticket_id, "ticketHash": _hash(record)}, at=now)
            self._write(state)
            return record

    def _expire_locked(self, state: dict[str, Any], now: datetime, ticket_id: str | None = None) -> list[dict[str, Any]]:
        expired: list[dict[str, Any]] = []
        tickets = state["tickets"].values() if ticket_id is None else [state["tickets"].get(ticket_id)]
        for ticket in tickets:
            if not ticket or ticket.get("status") != "claimed":
                continue
            claim = ticket.get("claim", {})
            if _parse_time(claim.get("expiresAt", "")) <= now:
                claim_hash = _hash(claim)
                # Record expiry first, then return ticket to open for reclaim.
                ticket["status"] = "open"
                receipt = self._receipt(state, "expire", "pass", details={"ticketId": ticket["id"], "owner": claim.get("owner"), "claimHash": claim_hash, "expiredAt": claim.get("expiresAt")}, at=now)
                ticket["lastExpiryReceipt"] = receipt["id"]
                expired.append(receipt)
        return expired

    def expire(self, ticket_id: str | None = None) -> list[dict[str, Any]]:
        now = self.clock()
        with self._locked():
            state = self._read_state()
            if ticket_id is not None and ticket_id not in state["tickets"]:
                raise InvalidOperation(f"unknown ticket {ticket_id!r}")
            receipts = self._expire_locked(state, now, ticket_id)
            if receipts:
                self._write(state)
            return receipts

    def claim(self, ticket_id: str, owner: str, *, ttl_seconds: int = 3600) -> dict[str, Any]:
        if not owner or ttl_seconds < 1:
            raise InvalidOperation("claim owner and positive ttl_seconds are required")
        registry, registry_hash = self._registry()
        blocks = self._registry_blocks(registry)
        now = self.clock()
        with self._locked():
            state = self._read_state()
            expired = self._expire_locked(state, now)
            ticket = state["tickets"].get(ticket_id)
            if ticket is None:
                raise InvalidOperation(f"unknown ticket {ticket_id!r}")
            block, dependencies, group = self._dependency_data(ticket["block"], registry, registry_hash)
            blocked = self._eligible(ticket["block"], block, dependencies, group, blocks, state, now)
            if blocked:
                receipt = self._receipt(state, "claim", "blocked", details={"ticketId": ticket_id, "blockedDependencies": blocked}, at=now)
                self._write(state)
                raise BlockedError(f"ticket prerequisites changed: {', '.join(blocked)} (receipt {receipt['id']})")
            if ticket.get("status") == "claimed":
                old_owner = ticket.get("claim", {}).get("owner")
                if old_owner == owner:
                    # Claim is idempotent; renewal remains explicit.
                    if expired:
                        self._write(state)
                    return ticket
                conflict = self._receipt(state, "claim", "conflict", details={"ticketId": ticket_id, "owner": owner, "heldBy": old_owner}, at=now)
                self._write(state)
                raise ConflictError(f"ticket held by {old_owner!r}; conflict receipt {conflict['id']}")
            if ticket.get("status") not in ("open", "expired"):
                conflict = self._receipt(state, "claim", "conflict", details={"ticketId": ticket_id, "status": ticket.get("status"), "owner": owner}, at=now)
                self._write(state)
                raise ConflictError(f"ticket cannot be claimed from status {ticket.get('status')!r}; receipt {conflict['id']}")
            # Same block can have only one live owner, even across duplicate tickets.
            other = next((t for t in state["tickets"].values() if t["id"] != ticket_id and t.get("block") == ticket["block"] and t.get("status") == "claimed"), None)
            if other:
                conflict = self._receipt(state, "claim", "conflict", details={"ticketId": ticket_id, "conflictWith": other["id"], "owner": owner}, at=now)
                self._write(state)
                raise ConflictError(f"block already claimed by ticket {other['id']!r}; receipt {conflict['id']}")
            claim = {"owner": owner, "claimedAt": _stamp(now), "expiresAt": _stamp(now + timedelta(seconds=ttl_seconds))}
            ticket["claim"] = claim
            ticket["status"] = "claimed"
            reclaimed = any(r.get("details", {}).get("ticketId") == ticket_id for r in expired)
            receipt = self._receipt(state, "claim", "pass", inputs=[{"id": "block-registry", "hash": registry_hash}], details={"ticketId": ticket_id, "owner": owner, "claimHash": _hash(claim), "reclaimedAfterExpiry": reclaimed}, at=now)
            ticket["lastClaimReceipt"] = receipt["id"]
            self._write(state)
            return ticket

    def renew(self, ticket_id: str, owner: str, *, ttl_seconds: int = 3600) -> dict[str, Any]:
        if ttl_seconds < 1:
            raise InvalidOperation("positive ttl_seconds is required")
        now = self.clock()
        with self._locked():
            state = self._read_state()
            self._expire_locked(state, now, ticket_id)
            ticket = state["tickets"].get(ticket_id)
            if ticket is None:
                raise InvalidOperation(f"unknown ticket {ticket_id!r}")
            claim = ticket.get("claim", {})
            if ticket.get("status") != "claimed" or claim.get("owner") != owner:
                self._write(state)
                raise ConflictError("only current unexpired claim owner may renew")
            previous = _hash(claim)
            claim["expiresAt"] = _stamp(now + timedelta(seconds=ttl_seconds))
            receipt = self._receipt(state, "renew", "pass", details={"ticketId": ticket_id, "owner": owner, "previousClaimHash": previous, "claimHash": _hash(claim)}, at=now)
            ticket["lastRenewalReceipt"] = receipt["id"]
            self._write(state)
            return ticket

    def close(self, ticket_id: str, gate_receipt: dict[str, Any]) -> dict[str, Any]:
        """Close only when a configured trusted verifier binds passing gate to ticket."""
        if self.gate_verifier is None:
            raise BlockedError("close requires trusted gate receipt verifier")
        verified = self.gate_verifier(gate_receipt)
        if verified is True:
            verified = gate_receipt
        if not isinstance(verified, dict) or verified.get("trusted") is not True:
            raise BlockedError("gate receipt did not verify as trusted")
        if verified.get("operation") != "gate" or verified.get("status") != "pass":
            raise InvalidOperation("only passing gate receipts can close tickets")
        receipt_hash = _hash(gate_receipt)
        now = self.clock()
        with self._locked():
            state = self._read_state()
            ticket = state["tickets"].get(ticket_id)
            if ticket is None:
                raise InvalidOperation(f"unknown ticket {ticket_id!r}")
            if verified.get("ticketId") != ticket_id or verified.get("block") != ticket.get("block"):
                raise InvalidOperation("gate receipt is not bound to this ticket and block")
            if ticket.get("status") == "closed":
                if ticket.get("gateReceipt", {}).get("hash") == receipt_hash:
                    return ticket
                raise ConflictError("closed ticket cannot be rebound to another gate receipt")
            if ticket.get("status") not in ("claimed", "open", "expired"):
                raise InvalidOperation(f"cannot close ticket with status {ticket.get('status')!r}")
            bound = {"id": str(gate_receipt.get("id", ticket_id)), "hash": receipt_hash}
            ticket["gateReceipt"] = bound
            ticket["status"] = "closed"
            self._receipt(state, "close", "pass", inputs=[bound], details={"ticketId": ticket_id, "block": ticket["block"], "trustedGate": True}, at=now)
            self._write(state)
            return ticket

    def get(self, ticket_id: str) -> dict[str, Any]:
        with self._locked():
            state = self._read_state()
            try:
                return state["tickets"][ticket_id]
            except KeyError as exc:
                raise InvalidOperation(f"unknown ticket {ticket_id!r}") from exc

    def list_tickets(self) -> list[dict[str, Any]]:
        with self._locked():
            return list(self._read_state()["tickets"].values())

    def list_receipts(self) -> list[dict[str, Any]]:
        with self._locked():
            return list(self._read_state()["receipts"].values())
