#!/usr/bin/env python3
"""Offline issuer ID/schema fault controls; no PowerShell/native effects."""
from __future__ import annotations
import copy, hashlib, importlib.util, json, re, uuid
from pathlib import Path
from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[5]
SCHEMA = json.loads((REPO / "factory/native/windows/settled-capture-adapter-v3/dependencies/common.schema.json").read_text())
ID_VALIDATOR = Draft202012Validator({"$defs": SCHEMA["$defs"], "$ref": "#/$defs/hashRef"})
ISSUER_SOURCE = (HERE / "issue-before-launch-prefixed-r1.ps1").read_text()

def ref(value: str) -> dict:
    return {"id": value, "hash": "sha256:" + "0" * 64}

def valid_id(value: str) -> bool:
    return not list(ID_VALIDATOR.iter_errors(ref(value)))

def fixture(count: int = 20):
    return [{"run": i, "captureID": f"capture/{uuid.uuid4().hex}", "imageID": f"image/{uuid.uuid4().hex}"} for i in range(1, count + 1)]

def admitted(rows):
    if len(rows) != 20 or [x["run"] for x in rows] != list(range(1, 21)):
        return False
    if len({x["captureID"] for x in rows}) != 20 or len({x["imageID"] for x in rows}) != 20:
        return False
    return all(valid_id(x["captureID"]) and valid_id(x["imageID"])
               and re.fullmatch(r"capture/[0-9a-f]{32}", x["captureID"])
               and re.fullmatch(r"image/[0-9a-f]{32}", x["imageID"])
               for x in rows)

def main():
    assert "$baseRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\\..'))" in ISSUER_SOURCE
    assert "$contextPath=Join-Path $baseRoot 'candidate-context.json'" in ISSUER_SOURCE
    assert "$expectedRun=Join-Path $baseRoot" in ISSUER_SOURCE
    assert "$expectedOutput=Join-Path (Join-Path $baseRoot" in ISSUER_SOURCE
    assert "Exact capture-v3 structural base root required" in ISSUER_SOURCE
    good = fixture()
    assert admitted(good)
    assert valid_id("capture/" + "a" * 32)
    assert valid_id("image/" + "f" * 32)
    # Real faults: schema-invalid bare GUID, wrong prefix, duplicate identity, wrong Count20 allocation.
    bare = copy.deepcopy(good); bare[0]["captureID"] = "1" + uuid.uuid4().hex[1:]
    wrong = copy.deepcopy(good); wrong[0]["imageID"] = "capture/" + uuid.uuid4().hex
    duplicate = copy.deepcopy(good); duplicate[1]["captureID"] = duplicate[0]["captureID"]
    short = good[:-1]
    assert not admitted(bare)
    assert not admitted(wrong)
    assert not admitted(duplicate)
    assert not admitted(short)
    assert not valid_id("1" + uuid.uuid4().hex[1:])
    assert not valid_id("capture/" + "A" * 32)
    print("PASS issuer GUID controls: schema-valid prefixed IDs, bare/wrong/duplicate/count faults rejected")

if __name__ == "__main__":
    main()
