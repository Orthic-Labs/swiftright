from __future__ import annotations

import json
import multiprocessing
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from factory.queue import BlockedError, ConflictError, InvalidOperation, QueueStore


def _claim_worker(queue_file: str, registry_file: str, ticket_id: str, owner: str, output) -> None:
    store = QueueStore(queue_file, registry_file)
    try:
        store.claim(ticket_id, owner, ttl_seconds=300)
        output.put((owner, "claimed"))
    except ConflictError:
        output.put((owner, "conflict"))


class MutableClock:
    def __init__(self) -> None:
        self.now = datetime(2026, 10, 10, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now

    def advance(self, **kwargs) -> None:
        self.now += timedelta(**kwargs)


class QueueStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.queue_file = self.root / "queue.json"
        self.registry_file = self.root / "registry.json"
        self.clock = MutableClock()
        self.registry = {
            "kind": "block-registry",
            "version": "0.1",
            "id": "registry/test",
            "provenance": {"sourceHash": "sha256:" + "1" * 64, "createdAt": "2026-10-10T12:00:00Z", "producer": "unit"},
            "blocks": [
                {"id": "foundation", "symbols": ["Foundation"], "inventoryStatus": "adapted", "progress": "not-started", "semanticDependencies": []},
                {"id": "widget", "symbols": ["Widget"], "inventoryStatus": "adapted", "progress": "not-started", "semanticDependencies": ["foundation"]},
            ],
        }
        self.write_registry()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_registry(self) -> None:
        self.registry_file.write_text(json.dumps(self.registry), encoding="utf-8")

    def store(self, **kwargs) -> QueueStore:
        return QueueStore(self.queue_file, self.registry_file, clock=self.clock, **kwargs)

    def test_ticket_dependency_claim_cannot_override_registry(self) -> None:
        submitted = {"id": "ticket/widget", "block": "widget", "dependencies": [], "status": "open"}
        with self.assertRaises(BlockedError):
            self.store().enqueue(submitted)
        self.registry["blocks"][0]["progress"] = "parity"
        self.write_registry()
        record = self.store().enqueue(submitted)
        self.assertEqual(record["dependencies"][0]["id"], "block/foundation")

    def test_same_declared_bootstrap_group_allows_enqueue(self) -> None:
        self.registry["blocks"][0]["bootstrapGroup"] = "boot-a"
        self.registry["blocks"][1]["bootstrapGroup"] = "boot-a"
        self.write_registry()
        self.assertEqual(self.store().enqueue("widget")["status"], "open")

    def test_concurrent_claim_has_one_winner_and_never_overwrites(self) -> None:
        self.registry["blocks"][1]["semanticDependencies"] = []
        self.write_registry()
        ticket = self.store().enqueue("widget")
        context = multiprocessing.get_context("spawn")
        output = context.Queue()
        processes = [
            context.Process(target=_claim_worker, args=(str(self.queue_file), str(self.registry_file), ticket["id"], owner, output))
            for owner in ("alice", "bob")
        ]
        for process in processes:
            process.start()
        outcomes = [output.get(timeout=10) for _ in processes]
        for process in processes:
            process.join(10)
            self.assertEqual(process.exitcode, 0)
        self.assertEqual(sorted(result for _, result in outcomes), ["claimed", "conflict"])
        final = self.store().get(ticket["id"])
        self.assertEqual(final["claim"]["owner"], next(owner for owner, result in outcomes if result == "claimed"))

    def test_expired_claim_reclaim_has_expiry_receipt(self) -> None:
        self.registry["blocks"][1]["semanticDependencies"] = []
        self.write_registry()
        store = self.store()
        ticket = store.enqueue("widget")
        store.claim(ticket["id"], "alice", ttl_seconds=2)
        self.clock.advance(seconds=3)
        reclaimed = store.claim(ticket["id"], "bob", ttl_seconds=60)
        self.assertEqual(reclaimed["claim"]["owner"], "bob")
        self.assertTrue(reclaimed["lastExpiryReceipt"].startswith("queue/"))
        expire_receipts = [r for r in store.list_receipts() if r["operation"] == "expire"]
        self.assertEqual(len(expire_receipts), 1)
        self.assertTrue(expire_receipts[0]["synthetic"])

    def test_close_requires_trusted_receipt_bound_to_ticket_and_block(self) -> None:
        self.registry["blocks"][1]["semanticDependencies"] = []
        self.write_registry()
        store = self.store(gate_verifier=lambda r: {**r, "trusted": True})
        ticket = store.enqueue("widget")
        passing = {"id": "gate/widget", "operation": "gate", "status": "pass", "ticketId": ticket["id"], "block": "widget"}
        with self.assertRaises(InvalidOperation):
            store.close(ticket["id"], {**passing, "block": "other"})
        closed = store.close(ticket["id"], passing)
        self.assertEqual(closed["status"], "closed")
        self.assertTrue(closed["gateReceipt"]["hash"].startswith("sha256:"))

    def test_scoped_maintainer_waiver_unblocks_queue_but_not_parity(self) -> None:
        def verify(waiver):
            return waiver.get("signature", {}).get("value") == "verified-test-signature"

        store = self.store(waiver_verifier=verify)
        waiver = {
            "kind": "waiver", "version": "0.1", "id": "waiver/widget-foundation",
            "scope": {"block": "widget", "dependency": "foundation"},
            "reason": "scoped unit fixture", "maintainer": "maintainer-1",
            "approvedAt": "2026-10-10T12:00:00Z", "expiresAt": "2026-10-10T13:00:00Z",
            "evidence": [{"id": "evidence/test", "hash": "sha256:" + "2" * 64}],
            "signature": {"keyId": "test-key", "value": "verified-test-signature"},
        }
        store.add_waiver(waiver, block="widget")
        self.assertEqual(store.enqueue("widget")["status"], "open")
        self.assertEqual(self.registry["blocks"][0]["progress"], "not-started")

    def test_waiver_requires_trusted_verifier_and_correct_scope(self) -> None:
        waiver = {"kind": "waiver", "version": "0.1", "id": "w", "scope": {"block": "widget", "dependency": "foundation"}}
        with self.assertRaises(BlockedError):
            self.store().add_waiver(waiver, block="widget")
        store = self.store(waiver_verifier=lambda _waiver: True)
        full = {
            **waiver, "reason": "test", "maintainer": "maintainer", "approvedAt": "2026-10-10T12:00:00Z",
            "expiresAt": "2026-10-10T13:00:00Z", "evidence": [{"id": "e", "hash": "sha256:" + "3" * 64}],
        }
        with self.assertRaises(InvalidOperation):
            store.add_waiver(full, block="foundation")


if __name__ == "__main__":
    unittest.main()
