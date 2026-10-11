# Seeded v1 proof namespace diagnosis

The 100-row mismatch is caused by the report selecting a different same-case/source archive, not by file drift between commit `51443310` and `HEAD`. `lineage.rawPath` is relative to `factory/oracle/mac/seed-corrections-v1`; its source archive reproduces proof + lineage raw and capture hashes for all 100 runs. The v1 report builder instead sets `MACROOT` to `factory/native/macos/evidence/20261010-gate-seeded`; that distinct capture batch matches its own summaries for all 100 runs and matches none of the proof raw/capture hashes.

For stack run 1, oracle raw SHA-256 is `040794666447c49109f1c9100230aa3276d5c56d2a35d6c80041b8997cb7771f` and oracle capture is `684ee57a1335fc8cfce293d536d6be7f36f647b5c0010830880a8647b3e5a044`. Native report raw is `f22329aca15b951798f76923b0381d8d67c62aa8c8b028647ce245e25f03e46b` and native capture is `13bd35e618567ca2e2f30ebc3359773ea7675d3cef786909fd12a9a610ef3082`. Committed bytes for each path are unchanged between `51443310` and `HEAD`. Proof copy did not exist at `51443310`; it was added at `7f95f113` and its hashes agree with the oracle archive.

This diagnosis only identifies correct provenance namespace. It does not rebind report or establish native parity, compiler process origin, shutdown, or qualification.
