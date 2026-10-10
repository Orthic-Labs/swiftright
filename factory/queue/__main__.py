"""CLI for staged local queue operations."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from .store import BlockedError, ConflictError, InvalidOperation, QueueStore


def _print(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Staged factory queue protocol v0.1 (unit mode)")
    parser.add_argument("--queue", required=True, help="queue state JSON path")
    parser.add_argument("--registry", help="trusted block-registry JSON path")
    sub = parser.add_subparsers(dest="command", required=True)

    enqueue = sub.add_parser("enqueue", help="enqueue eligible block")
    enqueue.add_argument("block")
    enqueue.add_argument("--report-link")
    claim = sub.add_parser("claim", help="claim ticket")
    claim.add_argument("ticket")
    claim.add_argument("owner")
    claim.add_argument("--ttl-seconds", type=int, default=3600)
    renew = sub.add_parser("renew", help="renew current claim")
    renew.add_argument("ticket")
    renew.add_argument("owner")
    renew.add_argument("--ttl-seconds", type=int, default=3600)
    expire = sub.add_parser("expire", help="record expired claims")
    expire.add_argument("ticket", nargs="?")
    show = sub.add_parser("show", help="show one ticket")
    show.add_argument("ticket")
    sub.add_parser("list", help="list tickets")

    args = parser.parse_args(argv)
    try:
        store = QueueStore(args.queue, args.registry)
        if args.command == "enqueue":
            result = store.enqueue(args.block, report_link=args.report_link)
        elif args.command == "claim":
            result = store.claim(args.ticket, args.owner, ttl_seconds=args.ttl_seconds)
        elif args.command == "renew":
            result = store.renew(args.ticket, args.owner, ttl_seconds=args.ttl_seconds)
        elif args.command == "expire":
            result = store.expire(args.ticket)
        elif args.command == "show":
            result = store.get(args.ticket)
        else:
            result = store.list_tickets()
        _print(result)
        return 0
    except BlockedError as exc:
        print(f"queue blocked: {exc}", file=sys.stderr)
        return 3
    except ConflictError as exc:
        print(f"queue conflict: {exc}", file=sys.stderr)
        return 1
    except (InvalidOperation, OSError, ValueError) as exc:
        print(f"queue invalid input: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # CLI boundary: keep internal faults distinct.
        print(f"queue internal fault: {exc}", file=sys.stderr)
        return 5


if __name__ == "__main__":
    raise SystemExit(main())
