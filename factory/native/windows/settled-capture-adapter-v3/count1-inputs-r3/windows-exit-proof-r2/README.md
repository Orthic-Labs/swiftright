# Windows exit proof r2

This successor keeps frozen `windows-exit-proof-r1` unchanged. It binds actual
r7 Count1 files through `r7-explicit-input-map-v2.json`:

- all 13 production proof roles;
- plan-bound host source rows (13);
- runtime source tree rows (21), resolved from measured module-origin source;
- two runtime module archives;
- compiler bytes from `compiler-byte-ref-r2.json`;
- native observation raw closure (24 files).

Generate source map:

```sh
python3 build-r7-explicit-map.py \
  --actual-map ../../../padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/count1-input-map-r7.actual.json \
  --adapter-inputs ../../../padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-inputs-r7.actual.json \
  --compiler-ref ../../../padding-capture-lease-capture-v3/root-actual-prefixed-v1/compiler-byte-ref-r2.json \
  --output r7-explicit-input-map-v2.json
```

Build plus run production reader gate:

```sh
python3 build-windows-exit-proof-r2.py \
  --captures ../../../padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-output-r7.actual.json \
  --input-map r7-explicit-input-map-v2.json \
  --output proof-bundle-r7-v2.json --verify-gate
```

Source controls pass. Bundle attaches one proof with exact archive bindings;
reader gate remains `blocked` on actual capture field absence
`actualSourceHash`; subsequent production fields include
`actualHostExecutableHash`, `actualRendererHash`, and sealed `rawHashStates`.
No source or native bytes are rewritten.
