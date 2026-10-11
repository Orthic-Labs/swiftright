import Foundation

// ABI0.6 clips are node-local; each paint leaf inherits intersected scroll viewports.
struct FactoryScrollClip: Equatable {
    let x: Float, y: Float, width: Float, height: Float
    init(x: Float, y: Float, width: Float, height: Float) throws {
        guard [x,y,width,height,x+width,y+height].allSatisfy({$0.isFinite}), width >= 0, height >= 0 else {
            throw NSError(domain:"FactoryInvalidScrollClip",code:1)
        }
        self.x=x; self.y=y; self.width=width; self.height=height
    }
}
func factoryInheritedScrollClip(_ inherited: FactoryScrollClip?, viewport: FactoryScrollClip) throws -> FactoryScrollClip {
    guard let inherited else { return viewport }
    let x=max(inherited.x,viewport.x), y=max(inherited.y,viewport.y)
    let right=min(inherited.x+inherited.width,viewport.x+viewport.width)
    let bottom=min(inherited.y+inherited.height,viewport.y+viewport.height)
    return try FactoryScrollClip(x:x,y:y,width:max(0,right-x),height:max(0,bottom-y))
}
// LayoutEngine has already subtracted offset. This helper never translates resolved paint bounds.
func factoryScrollPaintBounds(_ resolved: FactoryScrollClip) -> FactoryScrollClip { resolved }
