import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// Shared resolved-node -> ABI 0.6 paint mapper. It consumes runtime geometry/style
// exactly as resolved; witness-specific Graph construction stays in each main.swift.
struct FactorySharedNodeEmission {
    let primitives: [Primitive]
    let semantic: SemanticNode?
    let flags: NodeFlags
    let structural: Bool
}

struct FactorySharedNodeMapper {
    let scale: Float
    let textRun: (String, Font?, Rect) throws -> TextRunHandle

    func emit(_ node: ResolvedNode, bounds: Rect) throws -> FactorySharedNodeEmission {
        switch node.kind {
        case "Text":
            guard let text = node.text, !text.isEmpty else {
                return FactorySharedNodeEmission(primitives: [], semantic: nil,
                                                 flags: [], structural: false)
            }
            guard node.style.foreground == nil, node.opacity == 1 else {
                throw NSError(domain: "FactoryUnsupportedTextPaintStyle", code: 1)
            }
            let run = try textRun(text, node.style.font, bounds)
            return FactorySharedNodeEmission(
                primitives: [.text(run, x: bounds.x, y: bounds.y)],
                semantic: SemanticNode(role: .staticText, label: text,
                                       identifier: node.id,
                                       disabled: !node.accessibility.isEnabled),
                flags: [], structural: false)

        case "Button":
            let enabled = node.accessibility.isEnabled
            return FactorySharedNodeEmission(
                primitives: [.rect(bounds, color: enabled ? 0x2563ebff : 0xaaaaaaff,
                                   radius: 6 * scale)],
                semantic: SemanticNode(
                    role: .button,
                    label: node.accessibility.label ?? node.children.first?.text ?? "",
                    actions: enabled ? [.invoke, .focus] : [],
                    identifier: node.id,
                    disabled: !enabled),
                flags: [.hitTarget, .focusable], structural: false)

        case "Rectangle", "RoundedRectangle", "Circle":
            return FactorySharedNodeEmission(
                primitives: [try factorySharedShapePrimitive(node, bounds: bounds, scale: scale)],
                semantic: nil, flags: [], structural: false)

        case "Color":
            guard let color = node.color else {
                throw NSError(domain: "FactoryColorMetadataRequired", code: 1)
            }
            return FactorySharedNodeEmission(
                primitives: [.rect(bounds, color: try factorySharedResolvedFill(color,
                                                                                opacity: node.opacity))],
                semantic: nil, flags: [], structural: false)

        default:
            guard factorySharedIsStructuralContainer(node.kind) ||
                  node.kind.hasPrefix("modifier.") ||
                  node.kind.hasPrefix("Witness_") || node.kind == "Root" else {
                throw NSError(domain: "FactoryRendererUnsupportedNode", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: node.kind])
            }
            return FactorySharedNodeEmission(primitives: [], semantic: nil,
                                             flags: [], structural: true)
        }
    }
}

func factorySharedResolvedFill(_ value: ResolvedColor, opacity: Double) throws -> UInt32 {
    switch value {
    case .rgba(let r, let g, let b, let a):
        return try factoryRGBAFill([r, g, b, a], opacity: opacity)
    case .semantic(let name):
        guard opacity.isFinite, opacity >= 0, opacity <= 1 else {
            throw NSError(domain: "FactoryInvalidFillOpacity", code: 1)
        }
        let raw = try factorySemanticFill(name)
        return (raw & 0xffffff00) | UInt32((Double(raw & 255) * opacity).rounded())
    }
}

func factorySharedShapePrimitive(_ node: ResolvedNode, bounds: Rect,
                                scale: Float) throws -> Primitive {
    guard let shape = node.shape, let paint = shape.paint else {
        throw NSError(domain: "FactoryShapeMetadataRequired", code: 1)
    }
    let radius: Float
    let paintBounds: Rect
    switch shape.geometry {
    case .rectangle:
        radius = 0
        paintBounds = bounds
    case .circle:
        // Preserve existing factoryFillRect centering for non-square circles.
        let fill = try factoryFillRect(.circle, x: bounds.x, y: bounds.y,
                                       width: bounds.w, height: bounds.h)
        radius = fill.radius
        paintBounds = Rect(x: fill.x, y: fill.y, w: fill.width, h: fill.height)
    case .roundedRectangle(let cornerRadius, let style):
        guard style == .circular else {
            throw NSError(domain: "FactoryContinuousRoundedStrokeProviderHold", code: 78)
        }
        radius = min(Float(cornerRadius) * scale, min(bounds.w, bounds.h) / 2)
        paintBounds = bounds
    }
    switch paint.kind {
    case .fill:
        return .rect(paintBounds,
                     color: try factorySharedResolvedFill(paint.color, opacity: node.opacity),
                     radius: radius)
    case .stroke:
        guard let logicalWidth = paint.lineWidth,
              logicalWidth.isFinite, logicalWidth >= 0 else {
            throw NSError(domain: "FactoryShapeStrokeWidthRequired", code: 1)
        }
        return .rect(bounds, color: 0, radius: radius,
                     borderColor: try factorySharedResolvedFill(paint.color,
                                                                 opacity: node.opacity),
                     borderWidth: Float(logicalWidth) * scale)
    }
}

func factorySharedIsStructuralContainer(_ kind: String) -> Bool {
    switch kind {
    case "VStack", "HStack", "ZStack", "Overlay", "Layout", "Group", "EmptyView", "Spacer":
        return true
    default:
        return false
    }
}

// Host viewport policy shared by shape, stack, & custom-layout packets.
// It translates every resolved root-subtree node; host background stays fixed.
struct FactorySharedRootTranslation {
    let dx: Float
    let dy: Float

    func applying(to bounds: Rect) -> Rect {
        guard bounds.x.isFinite, bounds.y.isFinite,
              bounds.w.isFinite, bounds.h.isFinite else { return bounds }
        return Rect(x: bounds.x + dx, y: bounds.y + dy,
                    w: bounds.w, h: bounds.h)
    }
}

func factorySharedCenteredRootSubtree(_ rootBounds: Rect,
                                      viewport: Rect) -> FactorySharedRootTranslation? {
    guard rootBounds.x.isFinite, rootBounds.y.isFinite,
          rootBounds.w.isFinite, rootBounds.h.isFinite,
          viewport.x.isFinite, viewport.y.isFinite,
          viewport.w.isFinite, viewport.h.isFinite,
          rootBounds.w >= 0, rootBounds.h >= 0,
          viewport.w >= 0, viewport.h >= 0,
          rootBounds.w <= viewport.w, rootBounds.h <= viewport.h else {
        return nil
    }
    return FactorySharedRootTranslation(
        dx: viewport.x + (viewport.w - rootBounds.w) / 2 - rootBounds.x,
        dy: viewport.y + (viewport.h - rootBounds.h) / 2 - rootBounds.y)
}
