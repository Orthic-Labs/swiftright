#!/usr/bin/env python3
"""Adapter-v6 wrapper over frozen adapter-v5 with exact repeat-r7 source admission."""
from __future__ import annotations
import importlib.util, json
from pathlib import Path, PurePosixPath
HERE=Path(__file__).resolve().parent
V5=HERE.parent/'adapter-v5-source'/'adapter-v5.py'
spec=importlib.util.spec_from_file_location('frozen_adapter_v5',V5); frozen=importlib.util.module_from_spec(spec); assert spec.loader; spec.loader.exec_module(frozen)
PROFILE= json.loads((HERE.parent/'adapter-v5-source'/'repeat-r7-source-profile-v1'/'source-profile-repeat-r7.json').read_text())
R7_ROOT=PROFILE['overlayRoot']
R7_HASHES={PurePosixPath(x['path']).name:x['sha256'] for x in PROFILE['overlaySources']}
# Extend frozen support in memory only; no frozen source file is changed.
support=frozen._support
_frozen_overlay_v4=frozen._overlay_v4
support.OVERLAY_ROOTS.setdefault(20,{})[R7_ROOT]=dict(R7_HASHES)
support.SUCCESSOR_ROOTS.setdefault(20,set()).add(R7_ROOT)

def _overlay_v6(inputs,read_bytes):
 root=((inputs.get('executionOverlay') or {}).get('overlayRoot'))
 if root==R7_ROOT:
  frozen._overlay_v5(inputs,read_bytes)
 else:
  _frozen_overlay_v4(inputs,read_bytes)

# Frozen normalize resolves _overlay_v4 through module globals; replacing that
# function keeps every downstream proof/byte/schema guard unchanged.
frozen._overlay_v4=_overlay_v6
normalize=frozen.normalize
_overlay_v4=frozen._overlay_v4
validate_capture=frozen.validate_capture
SUPPORTED_PROFILES=frozen.SUPPORTED_PROFILES
