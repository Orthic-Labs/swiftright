Guard v2 preserves blocked v1 source/test byte snapshots in preimages/.

Compiler request authority lives in raw pinned plan.compileRequest with exact fields:
kind swiftpm-windows-gui-release/1, packagePath, scratchPath, compilerPath,
target windows-x86_64, configuration release. Production argv derives from
package/scratch + exact existing SwiftPM GUI flags; no caller argv whitelist.
Compile receipt must match derived argv, source cwd, compiler path + raw tool bytes,
target/configuration + exact expected Release-windows-x86_64 output path.
Original production invocation has implicit toolchain platform target; verifier
does not invent an explicit --triple flag. Missing request/path/target fields in
historical receipts block qualified admission; never retrofit raw evidence.

Cleanup status must belong to exact existing production terminal predicate:
already-signaled, signaled-after-exit-observation, signaled-during-lookup,
signaled-before-kill, signaled-during-kill, killed-owned-handle-signaled.
Wait0 + true flags with hold-cleanup still reject. Primary error always rejects.

Every coherent fault starts from its own passing synthetic fixture, mutates one
semantic authority/input, then refreshes incidental raw hashes. Malformed captures,
nested JSON objects + callback inputs fail closed. Synthetic fixture passes prove
structural controls only; native qualification count remains zero.

API + relative path reader contract remain v1: 13 exact raw roles, additional
host/<plan source path>, runtime/<runtimeTree source path>, tool/compiler.bin.
Core/workflow integration remains root-owned. No remote/native/Git actions.
