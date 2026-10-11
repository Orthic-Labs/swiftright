# Opt-in native-origin archive reader

`gate` & `gate-evidence` stay fail-closed when no archive reader is supplied.
To enable raw-byte origin verification, pass `--origin-reader-config` with
JSON shaped like:

```json
{
  "version": 1,
  "macRoots": ["archives/mac"],
  "windowsArchives": {
    "<64 lowercase hex chars from canonical capture hash>": "archives/windows/run-1"
  },
  "macPathMap": {
    "/usr/bin/xcrun": "archives/mac/tools/xcrun"
  }
}
```

Physical paths resolve relative to config file directory. `macRoots` admit
absolute receipt paths only beneath listed roots; `macPathMap` binds exact
logical Mac paths to archived files. `windowsArchives` binds each exact
canonical capture hash to one extracted capture directory. Reader returns
actual file bytes and verifies receipt hashes; platform guards still decide
whether each capture's process, source, case & tool evidence joins correctly.

Example:

```sh
python3 -m factory.pipeline gate --output .factory-work/gate-run \
  --evidence-root factory/native/macos/evidence \
  --origin-reader-config factory/pipeline/origin-reader.json
```

Config grants access to listed archive roots only; it does not grant native
parity, timing qualification, or promotion.
