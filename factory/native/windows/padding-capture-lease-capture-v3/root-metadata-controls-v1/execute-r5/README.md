# Count1 execute-r5 prefixed-ID overlay

Source-only successor from exact execute-r3. It changes only overlay script names & prefixed integration guard loading. Native capture body, constants, DllImport libraries, ABI, release, UIA, cleanup, & lock behavior remain byte-equivalent to execute-r3 after chain-name/guard normalization. `user32.dll` imports are pinned; no global digit rewrite is used.

Chain: `coordinator-r5.ps1` -> `interactive-task-r5.ps1` -> `dispatch-r5.ps1` -> `capture-repeat-r5.ps1`, plus hash-pinned `integration-prefixed-ids-r1.ps1`.

Offline check:

```text
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r5/test-execute-r5-source.py
```

No native, compiler, GUI, remote, or lock effects are performed by source checks.
