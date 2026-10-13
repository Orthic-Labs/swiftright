# Swift standard-library real import process capture v1

Bounded raw F1 capture for 16 Swift nominal owners named by held UI/Core source extensions. Existing `swift-stdlib-v1` facts remain unchanged. This sibling adds independently captured process receipts for a real `swiftc -typecheck` import probe, a real `source.request.indexsource` SourceKit run, & a real `swift-demangle --expand` run.

`swift-stdlib-process-evidence.json` keeps two identities per target:

- header-index witness from `external-owner-header-index-v1/swift-foundation/raw/Swift.index.txt`: `s:4main...`
- compiled import witness from fresh probe index: canonical Swift IDs such as `s:Sq`, `s:Si`, `s:Sm`.

Each target records physical name/kind/line/column/USR, public source facts & conditional stack, process argv/cwd/exit, stdout/stderr hashes, source/tool hashes, & full demangle tree/summary. No `main` to `Swift` alias rewrite or eligibility conclusion is made. Raw output is below 100 MB, so no chunking applies.

Initial demangle input/output & pre-final manifests remain under `attempts/` as lineage. Verify with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/catalogue/public-ancestor-spike/external-owner-capture/swift-stdlib-process-v1/verify_swift_stdlib_process.py
```
