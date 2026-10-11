# Copy-cost Mac packet correction v2

This append-only correction clarifies v1 evidence; original receipts, archives, source bindings, and stage manifest remain unchanged.

Stored `dynamicLinkage.stdoutSha256` hashes match exact stdout bytes recovered from frozen `*.otool-L.txt` by splitting at `\n--- stderr ---\n`. Full text-capture SHA differs because each text capture appends that delimiter and zero stderr bytes. `otool -L` is static load-command inspection; it is not runtime loaded-image evidence.

Correct test-method accounting: current 175/175 methods passed; candidate 174/175 methods passed, with one failed method and two failed assertions. Earlier 173-pass shorthand incorrectly counted assertions as methods.

The frozen v1 framework tarballs omitted `Versions/Current` symlink, so root framework alias would not resolve after extraction. Corrected v2 tarballs are generated only from frozen v1 archive bytes and add `Versions/Current -> A`; v1 archives are retained. Correction JSON records archive hashes, leaf hashes, raw capture hashes, and counts.
