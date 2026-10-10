# Dell interactive-session spike — 10 October 2026

Outcome: a second concurrently usable interactive session is not a qualified route on this Dell.
Keep native-only tests on the shared desktop, serialized by `D:\Claude\desktop.lock`, with foreground checks &
abort-on-focus-loss. Window-targeted input remains default; ordinary test windows remain in the background.

## Evidence

`session-preflight.ps1` ran read-only through existing `win` SSH helper. Raw output:
[`session-preflight-20261010.json`](session-preflight-20261010.json).

- Windows 11 Pro, build 26300, SKU 48, edition `Professional`.
- One active console session; SSH command runs in services session 0. RDP listener exists.
- Desktop lock belonged to SR0 run `r5-09`; this spike did not acquire, rewrite or release it.
- No window, native input, RDP login, user switch, policy change or deletion was performed.

Microsoft's [PowerToys session investigation](https://github.com/microsoft/PowerToys/blob/main/.github/skills/powertoys-verification/references/environment-setup.md#can-i-verify-two-modules-at-once-in-two-rdp-sessions)
documents client Windows session takeover: another RDP login disconnects the first interactive session, including
when using another user. Microsoft's [multi-session FAQ](https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-multisession-faq)
describes concurrent interactive sessions for Enterprise multi-session. This host inventory plus those sources
rules out treating a second RDP login on this Pro installation as non-disruptive isolation; no live takeover was attempted.

## Next native run

Reuse SR0's `drive-ime.ps1` & `drive-narrator.ps1` after frozen-contract dependencies clear. Both already check foreground
& abort on focus loss. Take the shared lock before any windowed run, retain the original owner if busy, & restore `free`
only after ending a run that owns it. A VM or different host is a separate, unqualified possibility, not second-session
evidence. Windows Sandbox's existing GPU limitations also prevent silently treating it as the native renderer lane.

Re-run the read-only inventory with:

```powershell
powershell -NoProfile -File factory\spikes\windows\session-preflight.ps1
```

This inventory establishes host feasibility only; it grants no IME, Narrator, renderer or parity PASS.
