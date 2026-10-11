import SwiftRightRuntime

// Separate prepared headless model control; never replaces original primary witness.
@MainActor func factoryScrollModelControl() {
    let graph=Graph(ScrollView(.horizontal) { Color.red.frame(width:200,height:20) }.frame(width:40,height:20))
    graph.flush()
    func find(_ node: ResolvedNode, _ kind: String) -> ResolvedNode? {
        if node.kind==kind { return node }
        for child in node.children { if let match=find(child,kind) { return match } }
        return nil
    }
    guard let root=graph.snapshot(), let scroll=find(root,"ScrollView"), let before=find(scroll,"Color") else { preconditionFailure("Missing real scroll snapshot") }
    graph.scroll(scroll.id,to:LayoutPoint(x:25,y:0));graph.flush()
    guard let afterRoot=graph.snapshot(), let after=find(afterRoot,"Color"), let offsets=graph.scrollOffsets(scroll.id) else { preconditionFailure("Missing offset snapshot") }
    precondition(offsets.x==25 && offsets.y==0)
    precondition(after.frame.minX==before.frame.minX-25)
    graph.scroll(scroll.id,to:LayoutPoint(x:1000,y:0));graph.flush()
    precondition(graph.scrollOffsets(scroll.id)?.x==160)
}
