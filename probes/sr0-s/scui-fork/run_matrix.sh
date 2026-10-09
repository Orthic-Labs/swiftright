#!/bin/bash
# usage: run_matrix.sh "<SCUI_STOCK list>"  -> one line per test (PASS/FAIL/SKIP/CRASH), each test in its own process.
cd "$(dirname "$0")"
export SCUI_STOCK="$1"
swift build --build-tests >/dev/null 2>&1 || { echo "BUILD FAILED"; exit 1; }
for t in $(grep -hoE "func test[A-Za-z0-9_]+" Tests/ScuiForkTests/SemanticTests.swift Tests/ScuiForkTests/BindingCollectionTests.swift Tests/ScuiForkTests/LayoutTests.swift 2>/dev/null | sed 's/func //'); do
  out=$(swift test --skip-build --filter "$t\$" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  if echo "$out" | grep -q "skipped"; then r=SKIP
  elif echo "$out" | grep -q "Fatal error\|unexpected signal"; then r="CRASH"
  elif echo "$out" | grep -q "' passed"; then r=PASS
  else r=FAIL; fi
  echo "$r $t"
done
