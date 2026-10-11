# Workflow reader repair v2

Successor to frozen v1. `prepare`, `gate` & `gate_evidence` use `artifact_reader` for tuple/config/recipe/manifest/capture bytes while `origin_reader` remains native-origin-only. Probe generation receives temporary witness roots populated only from reader-verified bytes, so generator path reads cannot bypass verification. v1 is preserved unchanged.
