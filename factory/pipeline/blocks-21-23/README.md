# Blocks 21 (swiftui.observation), 22 (swiftui.task-asyncstream) and 23 (swiftui.spacer-divider), SR1 round 4

Requested by the Pulse hub track (`docs/hub-track.md`, `docs/probes/hub-base-gap-check.md`: P13 `.task`, P14/P14b `@Observable`/`@Bindable`, P19 `Spacer`/`Divider` compiled on Windows but nothing proved how they behave).
`make_cases.py` writes every case (`new-case.py`: package/ + mac-source/ with a byte-identical Witness.swift, plus pair.json with the gates and the interaction steps); `run-n20.sh <stage> [runs] [case...]` runs the pairs on one staged product build (`python3 factory/tools/stage-product.py`).
Hosts are the blocks 11-16 hosts (`shared-mac-host`, `shared-windows-host`): an offscreen `NSHostingView` on the Mac, the shared capture host in the Windows Sandbox, both with the F2 step vocabulary (click, key, wait, dump, shot).

## How a case is built

- **Geometry.** The witness is a 240 x 200 pt frame centred in the 320 x 240 pt viewport (origin (40, 20) pt). Rows have fixed frames; a Button is clicked at the centre of its fixed frame (`px()` in `make_cases.py`).
- **Phases.** Every step list is `wait`, then per phase `click`, `wait`, `dump <label>`, `shot <label>`. `pair.json` `phaseShots` makes `pair.py` compare each labelled PNG pixel for pixel like the final capture (decision E1); `semanticGate.phases` compares the UI Automation tree against the Mac accessibility tree after every event.
- **Text and Button rows are excluded from the pixels by name** (Segoe UI vs SF, decision 2; Button width, decision 11) and gated by the tree (role, name, enabled, count, order). The colour squares and swatches are gated by pixels.
- **Observation is made visible with a stamp** (decision E2). `Box.stamp` is a plain global that view bodies read and observation does not track; a Button bumps it before it changes a model. A body that re-ran shows the new stamp (in a colour swatch and in its text), a body that did not re-run still shows the old one: that is "re-renders only the dependent views", and the negative case (a view that must NOT update), decided by both pixels and tree.
- **Events are pumped by hand** (decision E3). The task cases feed an `AsyncStream` whose continuation is yielded only by a Button the host clicks (one click = one event, `Burst` = three yields in one click). Nothing waits on a timer: the host's settle waits only give the main actor time to run what the click made runnable. No manual clock is needed, because no case depends on wall-clock time.

## Cases

| Block | Case | What it decides |
| --- | --- | --- |
| 21 observation | `property-render-v1` | one property, one reader: a meter of squares and a text follow the model |
| | `independent-readers-v1` | negative: changing `b` must not re-run the reader of `a`, and the reverse |
| | `nested-models-v1` | negative x2: an unread outer property and the retired inner model change nothing; the reader follows a swapped inner model |
| | `collection-of-models-v1` | toggling one item re-runs that row only; appending keeps the rows already shown |
| | `bindable-binding-v1` | `@Bindable` `$s.on` writes the model; only readers of `on` follow |
| | `computed-dependency-v1` | a computed property depends on its stored properties |
| 22 task-asyncstream | `stream-drives-state-v1` | `.task { for await }` drives state; `phase` shows the task started on appear |
| | `ordering-clicks-v1` | events 3,1,2,3 arrive in order, one per click |
| | `ordering-burst-v1` | three events yielded inside one click arrive in order, then more clicks |
| | `cancel-on-disappear-v1` | negative: the view that owns the task disappears; a later event does NOT apply (the statement after the loop still runs, as in SwiftUI) |
| | `task-id-restart-v1` | `.task(id:)` restarts on an id change; an event sent to the old run's stream does NOT apply |
| | `stream-finish-v1` | finishing the stream ends the loop, the code after it runs, a later event does nothing |
| 23 spacer-divider | `spacer-hstack-v1`, `spacer-vstack-v1`, `spacer-minlength-v1`, `spacer-flexible-v1`, `spacer-default-length-v1`, `spacer-spacing-v1`, `spacer-fixed-frame-v1`, `spacer-ties-v1` | Spacer: distribution, `minLength` (overflow keeps it), the nil default (8 pt), default vs explicit spacing next to a Spacer, fixed frames, odd-point (half-pixel) edges |
| | `divider-horizontal-v1`, `divider-vertical-v1`, `divider-vertical-fill-v1`, `divider-spacing-v1`, `divider-colour-v1`, `divider-ties-v1`, `divider-over-colour-v1` | Divider: orientation, thickness, separator colour and its alpha over a colour, fill, overlay, odd-point edges |
