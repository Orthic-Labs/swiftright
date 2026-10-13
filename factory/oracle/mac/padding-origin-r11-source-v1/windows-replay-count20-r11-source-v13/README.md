# Fresh r11 Count1 metadata admission v13

This packet is source-only. It preserves v12 & earlier packets, changes Count1 identity checks to require `capture/<32 hex>` & `image/<32 hex>`, & keeps Count20 fresh tuple checks unchanged.

Root stages `issue-count20-fresh-r11-v5.ps1` for fresh Count20 `r13` metadata. Run `test-count1-metadata-controls-v7.ps1` against real legacy Count1 `coordinator-single-r1` metadata (`observed-count1-metadata-r2`), while Count20 full controls target fresh `r13`. Controls include admitted baseline, relocated resealed baseline, & 11 independently resealed rejected mutations. Native, lock, compiler, GUI, & remote action counters must remain zero.

The issuer allocates prefixed IDs before launch & records `pending-actual-launch-joins`; it does not relabel historical observations. Root supplies exact fresh paths, measured hashes, source-equivalence receipt, serializer hash, & Mac schema nonce.
