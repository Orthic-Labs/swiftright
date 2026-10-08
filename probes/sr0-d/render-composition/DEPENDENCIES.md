# SR0-D render-composition: dependency facts

Status: resolve, check & x64 release build PASS on Windows x64 (Dell XPS 15, Windows 11 Pro 26300, Rust 1.98.0). Native UIA/IME behaviour NOT yet exercised.

## Evidence

| Step | RightKit request | Result |
|---|---|---|
| `cargo check --target x86_64-pc-windows-msvc` | `rr-1791482718474-47f776a9f74ca0bd` | exit 0, 719 packages locked |
| `cargo build --release --target x86_64-pc-windows-msvc` | `rr-1791483639920-056fd69ccf4882d0` | receipt SUCCEEDED, exit 0, 329 s |

- `Cargo.lock` was copied verbatim (line endings normalized) from the RightKit Windows replica; RightKit's remote route does not return it and denies `generate-lockfile`, `tree` & `metadata`.
- Built exe (11.5 MB) stays in RightKit-managed Windows target storage, outside Git.

## Direct dependencies (exact-pinned, Windows-only)

| Crate | Version | License |
|---|---|---|
| gpui | 0.2.2 | Apache-2.0 |
| accesskit | 0.25.1 | MIT OR Apache-2.0 |
| accesskit_windows | 0.35.1 | MIT OR Apache-2.0 |
| raw-window-handle | 0.6.2 | MIT OR Apache-2.0 OR Zlib |

GPUI uses `windows` 0.61.3; accesskit_windows uses `windows` 0.62.2. The probe bridges HWND by raw pointer through accesskit_windows' re-exported type.

## Full graph

[`licenses.tsv`](licenses.tsv) lists all 719 locked packages. Sources: all crates.io; no git or path sources. Licences were read from each package's `Cargo.toml` in the Windows Cargo registry caches.

- 656 packages downloaded for the Windows build: every one offers a permissive licence (MIT, Apache-2.0, BSD, ISC, Zlib, Unicode-3.0, CC0, 0BSD, BSL-1.0, NCSA or combinations).
- Copyleft appears only as an `OR` alternative: `r-efi` (MIT OR Apache-2.0 OR LGPL), `self_cell` (Apache-2.0 OR GPL-2.0). Choose the permissive option.
- One weak-copyleft package: `option-ext` 0.2.0, MPL-2.0 (file-level). Redistribution allowed; MPL source-availability notice required for that crate.
- 63 packages were not downloaded for the Windows target (macOS, Linux/Wayland/X11 and build-only crates such as `cocoa`, `metal`, `xcb`, `cosmic-text`). They are not compiled into the Windows binary; their licences are unverified.

## Native UIA result (2026-10-09, interactive desktop, rebuild `rr-1791484766375-bc56a6dc295f2cf6`)

Run by `scripts/uia-check.ps1` from the Windows desktop session; result & stderr re-read from the host by the primary session.

| Check | Result |
|---|---|
| Window shown after hidden create + adapter attach | PASS (`IsWindowVisible` true; not confirmed by eye) |
| SwiftRight-authored tree published | PASS: Window > Button "Probe" (Invoke) + Edit "Probe input" (Value) |
| UIA Invoke / SetFocus / SetValue reach action handler | PASS: Focus #2, Click #2, Focus #3, SetValue #3 "hello" logged |

Findings for SR0-B:
- Edit exposes ValuePattern only, no TextPattern. Required editable-text reading, selection & caret ranges need text-run nodes; not yet proven.
- Coordinate space is unverified: UIA reported the window as 1632x1288 for a 640x480 logical request, while hand-authored node bounds came through unscaled (button 120x40). SR0-B must fix DPI/physical-pixel conversion before paint/AX bounds agreement can pass.
- Action handler ran without touching GPUI; enqueue-to-UI-thread routing is not yet exercised.

## Open for SR0-D

- IMM32 composition into a SwiftRight-owned text node.
- Windows arm64: no host (Dell XPS 15 is x64); lane blocked.
