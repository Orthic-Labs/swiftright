# Round2 extra F4 generator proposal

Versioned source-only successor for five held Round2 recipes. It reuses frozen recipe witnesses, candidate registry selectors, source-use joins, & validation descriptor IDs/inputs. It emits 19 Swift sources & JSON manifests without compiler/native execution, tuple claims, callbacks, or active registry changes.

`generate.py --check-only` validates frozen pins & policy. `generate.py --output-dir <fresh-directory>` emits one pair per frozen descriptor. Output marks `executionEligible=false`, records compile expectation only, & gives explicit blocked observability reasons for popover, spring presentation, IME, environment layout/paint, context menu, events, & accessibility channels.

Controls reject candidate USR/source misbinding, duplicate/unknown join blocks, recipe/source hash drift, frozen case ID/input drift, unsupported observation map drift, duplicate cases, promotion, unsafe placeholders, unresolved placeholders, & source/witness hash drift. Existing `factory/probes/generator.py` & active registry remain untouched. This packet claims no typecheck, native, tuple, or qualification result.

Run checks:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python3 factory/probes/round2-extra-generator-v1/generate.py --check-only
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/probes/round2-extra-generator-v1:. python3 factory/probes/round2-extra-generator-v1/test_generator.py
```
