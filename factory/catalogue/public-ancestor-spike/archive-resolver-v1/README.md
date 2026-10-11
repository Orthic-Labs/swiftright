# Archive resolver v1

Shared strict resolver for caller-pinned SDK, tool, header, modulemap, interface, & probe bytes. Production accepts only approved repository manifests:

- v1 `factory/catalogue/public-ancestor-spike/archive-inputs-v1/archive-input-mapping.json`, SHA-256 `57d10fa4184cd2585917ca721f94ac9270421ecfd4e2fcd187e0043bf5f49b75`
- v2 `factory/catalogue/public-ancestor-spike/archive-inputs-v2/archive-input-mapping.json`, SHA-256 `f1d53fde421d58b591c7e69eb35f3811db28785ca4cf15d244ba20b3cbd28dc8`

Manifest semantic paths remain exact absolute strings. `verify` checks exact path, hash, & size, then returns defensive copies. `read_bytes(..., force_archive=True)` reads only pinned repository plain or gzip bytes; it never consults live original paths or caches. Default reads exact live original bytes when present & hash-matching, then falls back to archive bytes when absent. Corrupt live bytes reject. `resolve_path` returns verified live paths or verified uncompressed archive paths; compressed archive callers use `read_bytes`.

Validation rejects duplicate originals, unapproved aliases, path escapes, symlink components, corrupt compressed/raw bytes, schema drift, malformed hashes, boolean integer fields, & truthy control flags. No compiler, SourceKit, GUI, permission, cache write, or source/tool execution occurs. Existing original argv/request paths remain untouched. Archive input ownership remains descriptor-only; SDK/tool bytes are not copied wholesale.

`prototype-prechange/` preserves original graph resolver source. `prechange-v2/` preserves pre-hardening source, controls, evidence, & checksums.

Run focused controls:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v factory/catalogue/public-ancestor-spike/archive-resolver-v1/test_archive_resolver.py
```
