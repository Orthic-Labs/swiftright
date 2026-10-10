# Final F1 context holds

`context-mismatch-evidence.json` records 206 rows held by finalized link evidence hash `sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`.

Each row joins exact module, line, name & raw SourceKit USR. Every row has one raw entity, exact kind & effective public access, plus final demangle coverage. Raw SourceKit context is empty for 33 rows & exact immediate suffix of interface context for 173. Interface scope receipts have depths 1:159, 2:41, 3:6.

Final demangled owner components equal interface lexical context after removing only explicit module qualification tokens for all 206. No genuine owner mismatch & no missing demangle remain. 93 demangles carry `(extension in Module):` owner marker; remaining 113 carry nominal owner path directly.

Current strict context gate rejects all 206 because raw SourceKit context is not exact interface context. Evidence supports review-only candidate `demangle-confirmed-context-recovery` for all 206, requiring exact raw line/name/kind/access, exact raw USR demangle, explicit empty/suffix context encoding, & independent cursor/range control. Current link promotion remains 0.

Controls mutate one pinned raw record: replacing context with expected context passes only context predicate; replacing it with `__wrong_context__` is rejected. No guessed USRs or relaxed catalogue matching are used.

Run:

```sh
python3 factory/catalogue/residual-investigation/investigate_contexts.py
```
