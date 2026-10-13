# Count1 r3 actual ref map

`count1-input-map-r3.pending.json` maps observed Count1 files, all producer profile rows, all plan source bindings, both runtime modules, all tuple source inputs, four executed r3 overlay files, & 25 native/worker/renderer refs. It is intentionally non-runnable until three exact remote files are fetched.

Missing exact fetches:

- `roles.case`: source package `case.json`, bytes/hash must equal issued case hash `sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d`.
- `roles.renderer`: configured `swiftright_render.dll`, exact SHA256 `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, bytes `11885056`.
- `runs[0].workerExe`: recorded `C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`, exact SHA256 `60c9b29843624dd8af6b6a7b26147753be6aeef65098b9a503cc50850afe410f`; `worker-exit.json` confirms hash.

No substitute renderer, case, or worker executable is valid. After fetch, replace only three `null` map values with safe archive-relative paths, rerun producer, then run v4 adapter. Current pending producer invocation fails closed at missing `roles.case`; it writes no output.

Observed source facts: issued metadata `26ab10c102f2536110c373271cb377d8acda1a6983cb1f8e00238ff4e49d74d2`; compile receipt `1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf`; executable `3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a`; renderer plan hash `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`; runtime modules are `0f55b5b61d955b9551b8f5aadb09a28fb3e6de82d5fca1a00b571726734ae0ae` & `c9ab9f1e40e616bacbb0e5a59255d60ecfcef4a64710d4a22b364d3d71298e7d`.
