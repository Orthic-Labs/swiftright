import Foundation
@testable import TraceKit

/// Loads files from Tests/TraceKitTests/Fixtures (copied from probes/sr0-o/ax-routes/out).
enum Fx {
    static func data(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    static func rawAX() throws -> RawAXNode {
        try JSONDecoder().decode(RawAXNode.self, from: data("ax-tree-run2.json"))
    }
}

enum IDs {
    static func row(_ n: Int) -> String {
        "5A5A5A5A-0000-4000-8000-" + String(format: "%012d", n)
    }
    static let insertedRow = "8739D4C7-C94E-4558-A75C-F30B5098BC08"
    static func modelKey(_ uuid: String) -> String { "row/" + uuid }
    static func fieldId(_ uuid: String) -> String { "row/\(uuid)/field" }
    static func appear(_ uuid: String) -> LifecycleEvent { LifecycleEvent(kind: "appear", node: modelKey(uuid)) }
}

/// Accepted F1 trace. Model text, focus, selection, lifecycle and the AX snapshot come from the real
/// Mac probe run 2 (`probes/sr0-o/ax-routes/out`). The probe logged only row 5's text per step, so
/// other rows use the fixture's initial text "Row N" (see FixtureApp `Row(... text: "Row \(n)")`).
enum F1Baseline {
    static let sourceHash = "sha256:018d52e5c9020487b4030937f7891c7e5db1a432b847ffcebc6184dfeb029966"

    static func accepted() throws -> Trace {
        let stepsJSON = try JSONSerialization.jsonObject(with: Fx.data("f1-lite-steps.json")) as? [[String: Any]] ?? []
        let eventLines = String(decoding: try Fx.data("fixture-events-run2.jsonl"), as: UTF8.self)
            .split(separator: "\n").compactMap { line -> [String: String]? in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String]
            }
        let appearEvents = eventLines.filter { $0["ev"] == "appear" }
        let initialRows = appearEvents.filter { $0["row"] != IDs.insertedRow }
        let insertEvents = appearEvents.filter { $0["row"] == IDs.insertedRow }

        let rawAX = try Fx.rawAX()
        let axNodes = MacAXNormalizer.normalize(rawAX)

        var steps: [TraceStep] = [
            TraceStep(id: "initial", logicalAction: "launch-and-snapshot", nativeMapping: "AX tree walk from application root", timestamp: "1791486669.06"),
        ]
        var observations: [Observation] = []

        // Initial state: ten rows, the AX snapshot was taken here (row 5 reads "Row 5", no focus).
        var initialModel: [String: String] = [:]
        for n in 1...10 { initialModel[IDs.modelKey(IDs.row(n))] = "Row \(n)" }
        observations.append(Observation(
            stepId: "initial", model: initialModel, focusedNodeId: nil, selection: nil,
            lifecycle: initialRows.compactMap { $0["row"] }.map { LifecycleEvent(kind: "appear", node: IDs.modelKey($0)) },
            effects: [], axNodes: axNodes
        ))

        let names: [(String, String, String)] = [
            ("after_focus", "set-focus-and-caret-end", "AXFocused=true on row/5/field; AXSelectedTextRange=end"),
            ("after_type_abc", "type-abc", "CGEvent.postToPid(fixture) 'abc'"),
            ("after_axpress_insert", "activate-insert-above", "AXPress toolbar/insert"),
            ("after_type_d", "type-d", "CGEvent.postToPid(fixture) 'd'"),
        ]
        for (i, (stepId, action, mapping)) in names.enumerated() {
            let probe = stepsJSON[i]
            steps.append(TraceStep(id: stepId, logicalAction: action, nativeMapping: mapping, timestamp: "probe-step-\(i + 1)"))

            var model = initialModel
            model[IDs.modelKey(IDs.row(5))] = probe["row5Value"] as? String ?? "?"
            let inserted = i >= 2   // insert happens in the third probe step
            if inserted { model[IDs.modelKey(IDs.insertedRow)] = "Inserted" }
            precondition(model.count == (probe["rowFieldCount"] as? Int ?? -1), "row count mismatch at \(stepId)")

            let sel = probe["selectedRange"] as? [String: Int]
            observations.append(Observation(
                stepId: stepId,
                model: model,
                focusedNodeId: probe["focusedIdentifier"] as? String,
                selection: sel.map { UTF16Range(location: $0["location"] ?? 0, length: $0["length"] ?? 0) },
                lifecycle: inserted ? insertEvents.compactMap { $0["row"] }.map { LifecycleEvent(kind: "appear", node: IDs.modelKey($0)) } : [],
                effects: inserted ? ["insert-row index=0 row=\(IDs.insertedRow)"] : [],
                axNodes: nil
            ))
        }

        return Trace(
            schemaVersion: traceSchemaVersion,
            fixtureId: "F1",
            sourceHash: sourceHash,
            platform: PlatformTuple(os: "macos", osBuild: "27.0.1 (26A434)", arch: "arm64",
                                    toolchain: "Swift 6.4 swiftlang-6.4.0.34.1"),
            steps: steps,
            observations: observations,
            declaredOrder: []   // the probe recorded no lifecycle ordering constraints
        )
    }
}

/// Synthetic F4 baseline (stale async). Test-authored, NOT recorded on macOS: the probe recorded no tasks.
/// It exists to exercise task-lifecycle comparison and the stale-commit fault.
enum F4SyntheticBaseline {
    static let sourceHash = "synthetic:test-authored"

    static func accepted() -> Trace {
        let row5 = IDs.modelKey(IDs.row(5))
        return Trace(
            schemaVersion: traceSchemaVersion,
            fixtureId: "F4",
            sourceHash: sourceHash,
            platform: PlatformTuple(os: "macos", osBuild: "synthetic", arch: "arm64", toolchain: "synthetic"),
            steps: [
                TraceStep(id: "start_task", logicalAction: "focus row 5 and start its async update", nativeMapping: "fixture stimulus", timestamp: "t1"),
                TraceStep(id: "remove_row", logicalAction: "delete row 5 via model command", nativeMapping: "fixture stimulus", timestamp: "t2"),
                TraceStep(id: "release_completion", logicalAction: "fake engine releases the completion", nativeMapping: "fake engine", timestamp: "t3"),
            ],
            observations: [
                Observation(stepId: "start_task", model: [row5: "Row 5"], focusedNodeId: IDs.fieldId(IDs.row(5)), selection: nil,
                            lifecycle: [IDs.appear(IDs.row(5)), LifecycleEvent(kind: "taskStart", node: row5)],
                            effects: [], axNodes: nil),
                Observation(stepId: "remove_row", model: [:], focusedNodeId: nil, selection: nil,
                            lifecycle: [LifecycleEvent(kind: "disappear", node: row5), LifecycleEvent(kind: "taskCancel", node: row5)],
                            effects: ["remove-row \(row5)"], axNodes: nil),
                Observation(stepId: "release_completion", model: [:], focusedNodeId: nil, selection: nil,
                            lifecycle: [], effects: [], axNodes: nil),
            ],
            declaredOrder: [
                OrderEdge(before: "taskStart:\(row5)", after: "taskCancel:\(row5)"),
                OrderEdge(before: "disappear:\(row5)", after: "taskCancel:\(row5)"),
            ]
        )
    }
}

/// Raw-level helpers for AX faults.
enum RawEdit {
    static func map(_ n: RawAXNode, _ f: (RawAXNode) -> RawAXNode) -> RawAXNode {
        var m = f(n)
        if let children = m.children { m.children = children.map { map($0, f) } }
        return m
    }

    /// Wraps every AXOutline in an unlisted container role.
    static func wrapOutline(_ n: RawAXNode) -> RawAXNode {
        var m = n
        m.children = n.children?.map(wrapOutline)
        if n.role == "AXOutline" {
            return RawAXNode(role: "AXSplitGroup", children: [m])
        }
        return m
    }
}
