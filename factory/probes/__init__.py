"""Deterministic Swift probe generation for factory recipes & cases."""

from .generator import ProbeError, generate_probe

__all__ = ["ProbeError", "generate_probe"]
