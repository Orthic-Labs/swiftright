import Foundation
import Testing
import TraceKit
@testable import UIAKit

@Suite struct WinNormalizerTests {
    func sample() -> UIANode {
        UIANode(index: 0, controlType: "Window", automationId: "main", name: "App", children: [
            UIANode(index: 1, controlType: "Pane", children: [
                UIANode(index: 2, controlType: "Button", automationId: "toolbar/insert", name: "Insert above", patterns: ["InvokePattern"]),
                UIANode(index: 3, controlType: "Edit", name: "Edit", value: "a",
                        patterns: ["ValuePattern", "TextPattern", "LegacyIAccessiblePattern"], hasFocus: true),
            ]),
        ])
    }

    @Test func stripsContainersAndMapsRoles() {
        let n = WinNormalizer.normalize(sample())
        #expect(n.nodes.map(\.role) == ["window", "button", "text-field"])
        #expect(n.nodes[1].parent == "main")
        #expect(n.nodes[1].order == 0 && n.nodes[2].order == 1)
    }

    @Test func dropsWindowChromeSubtree() {
        let t = UIANode(index: 0, controlType: "Window", children: [
            UIANode(index: 1, controlType: "TitleBar", children: [UIANode(index: 2, controlType: "Button", name: "Close")]),
            UIANode(index: 3, controlType: "Button", name: "Press me"),
        ])
        let n = WinNormalizer.normalize(t)
        #expect(n.nodes.map { $0.label ?? "-" } == ["-", "Press me"])
        #expect(n.nodes[1].order == 0 && n.nodes[1].id == "anon:anon:root#0#0")
    }

    @Test func actionsExcludeReadSurfaces() {
        let n = WinNormalizer.normalize(sample())
        #expect(n.nodes[1].actions == ["activate"])
        #expect(n.nodes[2].actions == ["set-value"])
    }

    @Test func idsAndIndexMap() {
        let n = WinNormalizer.normalize(sample())
        #expect(n.idByIndex[0] == "main")
        #expect(n.idByIndex[2] == "toolbar/insert")
        #expect(n.idByIndex[3] == "anon:main#1")
        #expect(n.idByIndex[1] == nil)   // stripped Pane
    }

    @Test func selectorResolves() {
        let t = sample()
        let n = WinNormalizer.normalize(t)
        #expect(Resolve.find(Selector(type: "Edit"), in: t, ids: n.idByIndex)?.index == 3)
        #expect(Resolve.find(Selector(id: "anon:main#1"), in: t, ids: n.idByIndex)?.index == 3)
        #expect(Resolve.find(Selector(name: "Insert above", type: "Button"), in: t, ids: n.idByIndex)?.index == 2)
        #expect(Resolve.find(Selector(name: "nope"), in: t, ids: n.idByIndex) == nil)
    }

    @Test func nativeMappingText() {
        let ops = [Op(op: "invoke", target: Selector(name: "Press me", type: "Button")), Op(op: "type", text: "a")]
        #expect(NativeMapping.describe(ops) == "UIA InvokePattern.Invoke [type=Button,name=Press me]; SendInput VK keys 'a'")
    }
}

@Suite struct SchemaCompatTests {
    @Test func mirrorTraceDecodesWithTraceKit() throws {
        let node = WNode(id: "a", role: "button", label: "x", value: nil, actions: ["activate"], parent: nil, order: 0)
        let t = WTrace(schemaVersion: "sr0-o.trace/v0", fixtureId: "F", sourceHash: "h",
                       platform: WPlatform(os: "windows", osBuild: "10.0.26300", arch: "x64", toolchain: "Swift 6.4.0"),
                       steps: [WStep(id: "s", logicalAction: "l", nativeMapping: "n", timestamp: "t")],
                       observations: [WObservation(stepId: "s", model: ["k": "v"], focusedNodeId: "a",
                                                   selection: WRange(location: 1, length: 0), lifecycle: [], effects: [], axNodes: [node])],
                       declaredOrder: [])
        let decoded = try TraceCodec.decode(try encodeJSON(t))
        #expect(decoded.observations[0].axNodes?.first?.id == "a")
        #expect(decoded.observations[0].selection?.location == 1 && decoded.observations[0].selection?.length == 0)
        #expect(decoded.schemaVersion == traceSchemaVersion)
        // and the round trip back through TraceKit's encoder is accepted by the mirror
        let back = try JSONDecoder().decode(WTrace.self, from: try TraceCodec.json(decoded))
        #expect(back == t)
    }
}
