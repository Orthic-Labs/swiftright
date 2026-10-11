# Padding window diagnosis actual compile review

Read-only audit of six fetched actual outputs from `root-build-r1/actual`. Build stage `b8db629c…7cfa` has 78 exact refs. Fetch receipt & local files agree byte-for-byte: compile receipt `74bf90f689d00124abbcfbe56a97b1160fe3117277c7e332490b48be713ca8d7`, GUI PE `caa9b760f2fc4574b0ca9846610f5b177b50e5180986c930415a442b3d83a369`, sealed stdout/stderr & two runtime module archives.

Receipt confirms exact diagnosis plan `aa6dcaf…6cdc`, source `b969817f…554b`, runtime commit `37429120`, release Windows x86_64 GUI argv, exit 0, kernel wait 0, timeout false, owned exit & complete raw drains. Independent PE parse reports machine 34404 & subsystem 2. Existing serializer control `952c7525…1bba` remains byte-bound; archived 13 source fault controls pass.

Decision: `CLEAR_ACTUAL_COMPILE_ONLY`; native parity, tuple & capture remain held.
