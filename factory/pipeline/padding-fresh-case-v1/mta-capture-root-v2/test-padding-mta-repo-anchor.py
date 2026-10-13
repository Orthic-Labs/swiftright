#!/usr/bin/env python3
"""Pure source control for MTA repository anchor; no packet/native actions."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('padding_mta_preparer',HERE/'prepare_padding_mta_root_v2.py')
if spec is None or spec.loader is None: raise RuntimeError('preparer import unavailable')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
if module.resolve_repo_anchor(HERE.parents[3]) != HERE.parents[3].resolve(): raise RuntimeError('correct repository anchor rejected')
for wrong in (HERE.parents[4], HERE.parents[2]):
    try:
        module.resolve_repo_anchor(wrong)
    except module.Hold:
        continue
    raise RuntimeError(f'wrong repository ancestor accepted: {wrong}')
print(json.dumps({'kind':'factory-padding-mta-repo-anchor-controls-v1','status':'SOURCE_REPO_ANCHOR_CONTROLS_PASS','correctAnchor':str(HERE.parents[3].resolve()),'wrongAncestorsRejected':2,'nativeActions':0,'compilerActions':0,'lockActions':0},sort_keys=True))
