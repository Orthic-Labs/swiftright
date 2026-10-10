"""Local reports for SwiftRight factory artifacts.

Input contract: ``registry`` is a block-registry object; cases, captures &
verdicts are lists, a single matching artifact object, or objects with matching
collection keys. ``demand`` optionally has
``blockCapabilities`` (block ID to capability-name list) and ``journeys`` (list
of objects with ``id``, optional ``name``, and ``blocks`` list). Pass status
requires optional ``gate_receipts`` containing a passing F10 receipt bound to
case, captures & tuple; receipt fields remain supplied evidence.
"""

from .report import build_report

__all__ = ["build_report"]
