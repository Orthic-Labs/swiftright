# Archive resolver v1

Shared strict resolver for immutable836 raw archive inputs. Production defaults are locked to repository archive manifest `factory/catalogue/raw-symbolgraph-archive-v1/archive-manifest.json`, exact manifest SHA-256 `6ddc54fe90bffd954f415963450cfa04d19d94070631b88619635826ce9139e3`, & immutable link SHA-256 `836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`.

`ArchiveResolver.verify` validates original semantic path/hash mappings. `read_bytes(..., force_archive=True)` reads only pinned repository plain, gzip, or chunk bytes; it never consults live original paths or caches. Default reads exact live original bytes when present & hash-matching, then falls back to archive bytes when absent. Corrupt live bytes reject. `resolve_path` returns verified live paths; chunked archive callers use `read_bytes`.

Manifest validation rejects duplicate originals, aliases, path escapes, symlink components, corrupt compressed/raw bytes, schema drift, malformed hashes, & boolean integer fields. No compiler, SourceKit, GUI, permission, or source/tool execution occurs. Existing original argv/request paths remain untouched. Source/tool origin pins remain upstream archive evidence.

Run focused controls:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v factory/catalogue/public-ancestor-spike/archive-resolver-v1/test_archive_resolver.py
```
