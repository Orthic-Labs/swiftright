The first `actual-final-r1-transport` receipt belongs to an earlier remote script invocation. Its recorded script hash differs from this packet's invocation hash; it is not proof of a new compiler run. All raw bytes remain unchanged.

`actual-final-r1-fresh-transport` uses unique remote script & output paths and joins the actual script hash. Its terminal success and `actual-final-r1` archive establish the v7 final build. Root transport runner now rejects receipts whose script hash or script path differs from the dispatched invocation; future final staging paths include compile revision.
