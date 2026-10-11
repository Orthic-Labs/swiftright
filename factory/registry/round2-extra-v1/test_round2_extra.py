#!/usr/bin/env python3
import copy, json, tempfile
from pathlib import Path
from verify import check, load
from generate import CATALOGUE, canonical, sha

BASE = Path(__file__).with_name("candidate-manifest.json")

def assert_reject(mutator, label):
    m, _ = load(BASE); c, craw = load(CATALOGUE); mutator(m)
    e = check(m, c, craw)
    assert e, label


def main():
    m, _ = load(BASE); c, craw = load(CATALOGUE)
    assert not check(m,c,craw), check(m,c,craw)
    assert_reject(lambda x: x["blocks"][0]["symbols"][0].__setitem__("selector", "usr:s:wrong"), "wrong USR")
    assert_reject(lambda x: x["blocks"][0]["symbols"][0].__setitem__("path", "SwiftUI.View.other"), "wrong path")
    assert_reject(lambda x: x["blocks"][0]["symbols"].append(copy.deepcopy(x["blocks"][0]["symbols"][0])), "duplicate symbol")
    assert_reject(lambda x: x["blocks"][0].__setitem__("semanticDependencies", ["swiftui.toggle"]), "unbound dependency")
    assert_reject(lambda x: x["blocks"][0].__setitem__("registryPromotion", True), "promotion")
    assert_reject(lambda x: x["blocks"][0]["symbols"][0].__setitem__("symbolEvidenceSha256", "0"*64), "evidence hash")
    print(json.dumps({"ok":True,"acceptedBaseline":True,"rejectedControls":6},sort_keys=True))

if __name__ == "__main__": main()
