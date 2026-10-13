# SR1 root metadata controls review

Read-only source review of `factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1`.

Pinned inputs: stage manifest `51cc818f25949031b5551cf2824ebb966665874ef5d037514e821465f01f3135`; frozen integration `238b0df7a4f517babbbb2cb32133a2e4890ccb3b23839cd3dbdf5ae171270de4`; issuer `6d8ade4a46e4264af381543099f1474be3dabee5171e062389277e784ad0de35`; candidate context `705377b54e341e7cfc06eea4394bd7c5b9d92885e56165c0ee928a0e433c8de2`.

Static manifest replay found 15 entries with matching bytes & SHA-256. Python schema validator compiles. Source packet declares one actual baseline, relocated resealed positive, & 11 one-field faults; all controls require `nativeWindowActions=0`, `qualification=hold`. `Assert-LeaseIssuedMetadata` joins raw metadata, plan, compile receipt, executable, renderer, recipe, candidate tuple/binding, candidate context, canonical inputs, source binding, Mac context refs, runtime modules, & Count1 identities before any launch.

Concrete source hold: `enumerate-and-stage-input-refs.ps1` rejects POSIX/drive-rooted paths & `..`, but does not reject UNC (`\\server\share`) or drive-relative (`C:foo`) references, does not assert resolved destinations stay under `TransportRoot`, & permits `ManifestPath` outside fresh `TransportRoot`, where `Set-Content` could overwrite an existing file. Root should add containment checks before using dynamic transport. Dell actual issue-before-launch and PowerShell controls remain pending; no qualification claim.
