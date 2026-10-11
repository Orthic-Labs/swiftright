# Padding settled metrics v2

Fresh successor fixes JSON-boundary numeric boxing after v1 startup metrics serialization failure. Native snapshot passes explicit Double logical extents/scale into shared Foundation-only MetricsPayload.swift; raw event x/y & first-layout/window-close scale also become explicit Double. Integer identity fields remain exact. Encoding failures remain thrown errors & trigger existing host requestQuit behavior. Witness, viewport, graph, runtime receipts & ownership guards retain v1 behavior.

Headless serializer control compiles ONLY package/Sources/FactoryProbe/MetricsPayload.swift plus serializer-control/main.swift. It exercises shared snapshot/encoding functions, realistic ABI/owned-client bounds, raw event integer precision, first-layout, missing-event close, error fixtures & fail-closed invalid input. No renderer/window/native launch occurs. Console exit 0 plus SERIALIZER_CONTROL_PASS records=5 failClosed=true nativeLaunches=0 is required before fresh GUI capture. Legacy CGFloat validity diagnostic isolates Windows Foundation behavior.

source-manifest.json freezes all inputs. Builder v4 must rebind prospective package/plan runtime/bridge paths & source bindings into rolling .factory-work authority, using fresh build-settled-r2. No compile or execution performed in this source packet.
