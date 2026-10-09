| config | PASS/20 | raw distinct | canonical distinct | oracle-qualified? | runs present | relaunched |
|---|---|---|---|---|---|---|
| F1 | 20/20 | 1 | 1 | yes | 20 | 0 |
| F2 | 20/20 | 1 | 1 | yes | 20 | 0 |
| F3-list-0s | 20/20 | 3 | 1 | yes | 20 | 0 |
| F3-list-1s | 20/20 | 2 | 1 | yes | 20 | 0 |
| F3-list-3s | 20/20 | 2 | 1 | yes | 20 | 0 |
| F3-vstack-1s | 20/20 | 4 | 1 | yes | 20 | 0 |
| F3-vstack-3s | 20/20 | 2 | 1 | yes | 20 | 0 |
| F3-lazy-1s | 20/20 | 20 | 1 | yes | 20 | 0 |
| F3-lazy-3s | 20/20 | 20 | 1 | yes | 20 | 0 |
| F4 | 20/20 | 1 | 1 | yes | 20 | 0 |
| F5 | 20/20 | 1 | 1 | yes | 20 | 0 |
| F6 | 20/20 | 4 | 1 | yes | 20 | 0 |
| F6-reduced | 20/20 | 1 | 1 | yes | 20 | 0 |
| F7 | 20/20 | 1 | 1 | yes | 20 | 0 |
| F8 | 20/20 | 1 | 1 | yes | 20 | 0 |
| F9 | 20/20 | 2 | 1 | yes | 20 | 0 |

## F1
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0

## F2
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0

## F3-list-0s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 3; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 9

## F3-list-1s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 2; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 15

## F3-list-3s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 2; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 19

## F3-vstack-1s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 4; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 14

## F3-vstack-3s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 2; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 20

## F3-lazy-1s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 20; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 17

## F3-lazy-3s
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 20; canonical distinct: 1; runs with launch relaunch: 0
observe reinsert-focus: distinct values across runs = 1
observe reinsert-local-state: distinct values across runs = 15

## F4
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0

## F5
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0
observe zero-width-placement-passes: distinct values across runs = 1

## F6
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 4; canonical distinct: 1; runs with launch relaunch: 0

## F6-reduced
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0

## F7
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0

## F8
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 1; canonical distinct: 1; runs with launch relaunch: 0

## F9
runs present: 20/20; verdicts: Counter({'PASS': 20})
raw distinct: 2; canonical distinct: 1; runs with launch relaunch: 0
observe tree-released: distinct values across runs = 1
observe window-objects-after-close: distinct values across runs = 1

