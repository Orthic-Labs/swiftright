# Custom Layout RTL Mac Count1 request

Source packet: `factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/rtl-original-execution-v1`.

Run from repo checkout on Mac:

```sh
sh factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/rtl-original-execution-v1/mac-source/tools/prepare-mac-source.sh
sh factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/rtl-original-execution-v1/mac-source/tools/build-mac-source.sh
```

Run one preflight, then one observe invocation through existing `factory/tools/supervise-job-v2.py`, with `--rss-mib 256`, `--seconds 120`, `--log-mib 128`. Use fresh scratch `.../custom-layout-rtl-original-v1/scratch/count1`; retain stdout, stderr, supervision, `observation.json`, & `client.png` here. Stop if AX or screen-capture preflight is unavailable. No `/Volumes/D` binary or reused LTR capture.
