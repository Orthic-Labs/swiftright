# Swift sixteen genuine process capture v2

`capture_swift16.py --capture-only` executes pinned absolute Swift compiler, SourceKit-LSP & demangler through `subprocess.run`. Probe/request live on internal disk; archived copies preserve exact inputs. `processes.json` records actual argv, cwd, nanosecond start/end, return code, stdin hash & stdout/stderr bytes/hashes. No exit value comes from an existing stream, mtime or default.

`capture-inputs.json` freezes thirteen actual inputs. `exact_swift16.py` binds its exact hash & reconstructs sixteen public top-level physical Swift declarations from full SDK source/header index. Their raw nominal USRs retain `main`; ordinary imported canonical USRs retain `Swift`. Exact full trees bind both namespaces, names, nominal kinds & top-level owner paths. Optional's generic Never reference & Swift module reference are included in complete eighteen-reference closure.

`test_swift16.py` calls production guard after every accepted baseline, mutates actual raw source/index/reference/tree/request/process bytes & requires semantic rejection before final byte pins. Full source brace/conditional reconstruction uses frozen lexical code scanner; it does not call declaration-universe parser on unrelated multiline Swift local bindings.

`capture_swift16.py --finalize` validates frozen genuine receipts & rebuilds derived evidence without executing compilers. Repeating fresh captures requires a new version/freeze; fixed input manifest intentionally rejects replacement process timestamps. Initial genuine parser attempt & pre-final captures remain under `attempts/`.

Scope is sixteen exact physical-to-compiled-import correspondences. Original namespace mismatch remains explicit in every witness.
