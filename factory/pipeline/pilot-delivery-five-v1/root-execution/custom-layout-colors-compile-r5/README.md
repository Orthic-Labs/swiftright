# Custom layout direct-v7 compile-r5 incremental packet

Source-only successor correcting stale compile-plan packet identity while reusing existing v7 package.

- local & embedded plan: `plan-prebuild-v4.json`, SHA `sha256:ecf9ba5115bcafae8db6de14d1998201f2b5b56634d9177d18cad2ffa9547337`
- remote plan: `package\plan-prebuild-r5.json`, SHA `sha256:ecf9ba5115bcafae8db6de14d1998201f2b5b56634d9177d18cad2ffa9547337`
- embedded remote builder: `freshbuilder-r5.ps1`, SHA `sha256:7b9b26f0693665fe3078ab2a9de0af436b5a3f65384806fc06c72a3b28e4574c`
- self-contained incremental entry: `stage-build-r5-direct-v7.ps1`, SHA `sha256:1a9ea707af0fca9ea49e95bf8a25987b1d857e88f2a0e2fdf867cbece9df8ff8`
- existing package plan required: `sha256:6eae21b6d888c3c7f8abd7e564c62d259eafa45cc7d93ac185ce46da6fea701c`
- rolling stage: `D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors`

Entry embeds exact plan & builder bytes, verifies existing package, adds only fresh remote files, validates attempt-2 preflight JSON, then runs one bounded prebuild. r4 packet/evidence remains immutable.
