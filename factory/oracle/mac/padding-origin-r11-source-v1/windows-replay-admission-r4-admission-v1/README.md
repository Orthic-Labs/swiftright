# Strict source-equivalence admission r4

`admit-windows-replay-v4-equivalence.py` permits candidate reuse only when fresh & donor witness manifests have identical compiled semantic inputs: recipe, case inputs, channels, axes, source hash, witness type, & source file. It ignores only case metadata plus explicit sourceBinding. It still requires actual producer receipt, complete plan/proof/runtime/compiler closure, 20 trusted-reader rows, fresh tuple/case/manifest, fresh metadata, & fresh capture IDs. It scans executable bytes for donor/fresh case tokens. Historical r7 records remain immutable.

Against current r7 actual closure it returns `reuse-admitted-source-equivalent-v4`, exit `0`, with zero effects. Controls verify baseline plus semantic-input drift, binary case-token, & missing-proof-role rejects.

Fresh compile packet remains available under sibling `windows-replay-admission-r2` if any source or binary closure changes.
