# SR0 workload report (windows): INCOMPLETE

PASS refused:
- r1: window not displayed for most of the measured window (PresentMon: 3601 presents, 47 displayed, ~3600 expected): minimized, occluded by another window, or throttled
- set: W7 UI-only incremental build record present not measurable

| id | run | status | check | value | limit |
|---|---|---|---|---|---|
| P | r1 | PASS | DPI scale pinned | 2.5000 | == 2.5 |
| P | r1 | PASS | window size pinned (960x640 DIP) | True | bool True |
| P | r1 | PASS | ABI 0.6 | True | bool True |
| P | r1 | PASS | no debugger attached | True | bool True |
| P | r1 | PASS | full instrumentation level | True | bool True |
| W1 | r1 | PASS | wrong-node edits | 0 | == 0 |
| W1 | r1 | PASS | stale-owner result commits | 0 | == 0 |
| W1 | r1 | PASS | commits after window close | 0 | == 0 |
| W1 | r1 | PASS | row count constant (min=max=200) | True | bool True |
| W1 | r1 | PASS | unique stable row ids | True | bool True |
| W1 | r1 | PASS | run completed (app_exit complete, window closed) | True | bool True |
| W1 | r1 | PASS | cancellation exercised (stale results rejected > 0) | True | bool True |
| W1 | r1 | PASS | interrupted animation exercised | True | bool True |
| W0 | r1 | PASS | async ops delivered (>= 95% of 20/s) | True | bool True |
| W0 | r1 | PASS | reorders delivered (>= 1/s) | True | bool True |
| W1 | r1 | PASS | commit errors | 0 | == 0 |
| W1 | r1 | PASS | renderer commits rejected | 0 | == 0 |
| W1 | r1 | PASS | renderer live nodes after teardown | 0 | == 0 |
| W1 | r1 | PASS | renderer host panics / thread violations / reentry / dropped events | 0 | == 0 |
| W1 | r1 | PASS | measure/draw failures | 0 | == 0 |
| W1 | r1 | PASS | lost valid edits (posted up to measure end - applied) | 0 | == 0 |
| W1 | r1 | PASS | active text equals injected sequence | True | bool True |
| W2 | r1 | PASS | bridge time per input p95 (ms) | 0.5514 | <= 1.0 |
| W2 | r1 | PASS | bridge time per input p99 (ms) | 0.8550 | <= 2.0 |
| W3 | r1 | PASS | bridge time per committed frame p95 (ms) | 0.7356 | <= 2.0 |
| W3 | r1 | PASS | bridge time per committed frame p99 (ms) | 0.8390 | <= 4.0 |
| W6 | r1 | PASS | main-actor samples sufficient (starvation guard) | True | bool True |
| W6 | r1 | PASS | main-actor enqueue->exec p99 (ms) | 6.5732 | <= 16.7 |
| C | r1 | PASS | PresentMon rows in measured window (capture integrity) | True | bool True |
| W5 | r1 | PASS | refresh period measured (ms) within 60 Hz +-0.5% | True | bool True |
| W5 | r1 | INFO | missed vblanks (interval > 1.5 x refresh) [reported, not gated] | 31 | info 0 |
| W5 | r1 | FAIL | presented interval p95 (ms) <= refresh + 0.1 | 3999.4150 | <= 16.761000000000003 |
| CAL | r1 | PASS | clock correlation: |tick QPC - nearest present start| p95 (ms) | 0.1061 | <= 2.0 |
| W4 | r1 | PASS | every injected key in the window has a visible response | 0 | == 0 |
| W4 | r1 | FAIL | input->visible p95 (ms) | 3044.3844 | <= 50.0 |
| W4 | r1 | FAIL | input->visible p99 (ms) | 3844.3857 | <= 100.0 |
| CAL | r1 | PASS | keys in window (script delivered 10/s) | True | bool True |
| CAL | r1 | PASS | key schedule covers >= 90% of the measured window | True | bool True |
| W7 | set | MISSING | UI-only incremental build record present | None | bool True |

## Resources (informational; only a private-bytes slope above 5 MB/min is a threshold)

CPU: machine total %, our process in % of ONE core (100 = one core busy). Memory in MB with growth slope MB/min over the measured window. GPU: our process only, % summed per engine type per adapter.

| run | samples | CPU total avg/peak % | process avg/peak (core %) | busiest thread | pinned samples | working set avg/peak MB (slope/min) | private avg/peak MB (slope/min; app-only = trace buffers excluded) | handles max | threads max | GPU adapter used | sampler overhead (core %) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| r1 | not sampled | | | | | | | | | | |

| run | adapter | 3D avg/peak % | compute | copy | video | other | dedicated MB avg/peak | shared MB avg/peak |
|---|---|---|---|---|---|---|---|---|

Flags:
- r1: CONTEXT: user input during the key script: none (disturbed=false); foreground changes 0 []
- r1: CONTEXT: overlay hooks in the workload process: pre: modules=nvspcap64.dll procs=nvcontainer,NVDisplay.Container,NVIDIA (of 105 modules); post: modules=nvspcap64.dll procs=nvcontainer,NVDisplay.Container,NVIDIA (of 105 modules)
- r1: CONTEXT: busiest other processes over the key script (% of the whole machine): System(4):0.61;MsMpEng(56032):0.47;powershell(34540):0.42;svchost(36052):0.23;logioptionsplus_agent(12244):0.2;claude(59856):0.18
- r1: CONTEXT: msUntilRenderComplete p50 6.07 p95 10.46 p99 11.67 max 21.39 ms; dropped (replaced) presents 3554 of 3601

