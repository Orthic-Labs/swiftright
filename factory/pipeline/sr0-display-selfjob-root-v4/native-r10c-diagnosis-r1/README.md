# SR0 native-r10c release diagnosis

Archived run `factory/pipeline/sr0-display-selfjob-root-v4/actual-native-r10c`
is terminal-observed but lock-release ineligible. Collector failed before
workload row join: `workloadTargetPid:null`, `workloadProof:null`,
`failure: workload exit row count mismatch: 0 vs 1`. `result-workload.txt`
contains actual worker PID `48448`, exit 0, stream drains, and `runs_valid=1`.

Launcher proves retained coordinator/collector handles terminal with exit 1,
aggregate self-only active count 1, descendants quiesced, 1GiB flags 512, and
peak 703152128 bytes. Collector proves retained parent/workload/PresentMon
handles, workload exit 0, PresentMon forced stop -1, but
`presentMonStreamsSealed:null`, CSV/stderr evidence null, lock held, and
releaseAllowed false. Coordinator parent certificate is false.

`supplemental_release_v1.py` reads explicit receipts & bounded raw streams,
then emits release eligibility. It never reopens a PID, frees lock, stops a
process, or treats raw bytes as stream-seal proof:

```text
python3 factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-diagnosis-r1/supplemental_release_v1.py \
  --archive-root factory/pipeline/sr0-display-selfjob-root-v4/actual-native-r10c \
  --output .factory-work/sr0-r10c-diagnosis/supplemental-release.json
```

Required next-run corrections: join workload PID/path/start from bounded
`result-workload.txt` before row validation; retain exact workload ownership
proof; close/hash stdout/stderr before receipt publication; publish explicit
PresentMon stream-seal and CSV/stderr evidence; emit coordinator parent
certificate only after those checks. Keep desktop lock held until all pass.
