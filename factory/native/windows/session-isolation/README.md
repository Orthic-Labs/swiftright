# Read-only Windows session feasibility probe

Run metadata is in `probe.json`; literal captured Windows output is in `probe-output.txt`; conclusion & source links are in `assessment.md`. Probe uses only `qwinsta`, `quser`, CIM/service/registry reads and the existing `win` SSH wrapper. It never connects via RDP or interacts with desktop UI.
