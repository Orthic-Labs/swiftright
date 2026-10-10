# Identity & normalization tables v0.1

Each capture retains native tree & declares mapping version/hash. A normalized node maps `probeTag → stable view identity → Mac geometry/AX identity → Windows runtime node ID/AccessKit ID`; missing link blocks affected assertion. Normalizers may strip only protected-config, named platform-generated wrappers/IDs.

| Canonical role/action | macOS AX | Windows UIA |
| --- | --- | --- |
| button / activate | `AXButton` / `AXPress` | `Button` / `Invoke` |
| text field / set-value | `AXTextField` / `AXSetValue` | `Edit` / `Value` |
| static text | `AXStaticText` | `Text` |
| toggle / toggle | `AXCheckBox` / `AXPress` | `CheckBox` / `Toggle` |
| menu item / activate | `AXMenuItem` / `AXPress` | `MenuItem` / `Invoke` |

This table is a vocabulary seed, never an inferred allowance. Recipe/config names exact accepted role/pattern pairs. Provider & external-client captures are compared separately before shared semantic projection.

| Quantity | Canonical comparison unit | Conversion evidence |
| --- | --- | --- |
| Mac layout point | physical pixel | `px = point × mac capture scale` |
| Windows DIP | physical pixel | `px = dip × recorded DPI / 96` |
| Image edge | physical pixel | capture width, height & scale |

All scale/DPI values use tagged decimal or exact integer. Rounding, edge class tolerance, masks, & coordinate origin are acceptance configuration with hash & fault control; no blanket geometry tolerance exists.
