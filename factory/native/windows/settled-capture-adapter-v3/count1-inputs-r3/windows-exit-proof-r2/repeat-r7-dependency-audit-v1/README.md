# Repeat-r7 first-proof dependency audit

This source-only eight-entry closure repairs repeat-r6 scheduled child scope. `first-proof-repeat-r7.ps1` self-loads exact UIA `schema.ps1` bytes before first-proof functions, while dispatch & coordinator each dot-source helper. Audit checks all required function definitions, exact schema hash, both scheduled scopes, & schema/helper/parent-scope omission faults.

Run `python3 test-repeat-r7-dependency-closure.py`. No PowerShell, lock, GUI, compiler, remote, or native action occurs.
