# Factory workspace hygiene

Keep disposable runtime, host builds, staging & scratch inside ignored `.factory-work/` beneath SwiftRight checkout. Use rolling `runtime-stage` & `hosts` directories; never create `D:\Claude\factory-swiftright-*` siblings.

Mac fresh native binaries remain an exception required by capture policy: build & run only from internal-disk scratch, never `/Volumes/D`; retain required receipts before cleaning owned scratch. Never trigger permission prompts.

Before reusing or moving staging, confirm no owned process or running task needs it. Archive required evidence & hashes into factory evidence packets before retiring staging. Preserve frozen receipts; change prospective bindings in fresh packets.

Clean owned local scratch after every completed or aborted job. Never delete Dell files over SSH; move retired material into `D:\Claude\_factory-old-DELETE-ME` for Adrian to remove. Keep no retired build trees in active workspace.

Before reporting completion, verify active staging is ignored by Git & no owned staging remains outside checkout. Report cleanup completion separately from factory completion.
