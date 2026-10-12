import Foundation

// Native Windows observation palette; no Mac pixels or expected captures consumed.
enum FactoryFillGeometry { case rectangle, circle }
struct FactoryFillRect: Equatable {
    let x: Float, y: Float, width: Float, height: Float, radius: Float
}
func factoryFillRect(_ kind: FactoryFillGeometry, x: Float, y: Float, width: Float, height: Float) throws -> FactoryFillRect {
    guard [x,y,width,height].allSatisfy({$0.isFinite}), width >= 0, height >= 0 else {
        throw NSError(domain: "FactoryInvalidFillGeometry", code: 1)
    }
    switch kind {
    case .rectangle: return FactoryFillRect(x:x,y:y,width:width,height:height,radius:0)
    case .circle:
        let diameter = min(width,height)
        return FactoryFillRect(x:x+(width-diameter)/2,y:y+(height-diameter)/2,width:diameter,height:diameter,radius:diameter/2)
    }
}
func factorySemanticFill(_ name: String) throws -> UInt32 {
    let native: [String: UInt32] = ["system.red":0xff383cff,"system.blue":0x0088ffff,"black":0x000000ff,"white":0xffffffff,"clear":0]
    guard let value = native[name] else { throw NSError(domain: "FactoryUnsupportedSemanticFill", code: 1) }
    return value
}
func factoryRGBAFill(_ values: [Double], opacity: Double) throws -> UInt32 {
    guard values.count == 4, values.allSatisfy({$0.isFinite && $0 >= 0 && $0 <= 1}), opacity.isFinite, opacity >= 0, opacity <= 1 else {
        throw NSError(domain: "FactoryInvalidRGBAFill", code: 1)
    }
    let bytes=values.prefix(3).map { UInt32(($0*255).rounded()) }
    let alpha=UInt32((values[3]*opacity*255).rounded())
    return bytes[0]<<24 | bytes[1]<<16 | bytes[2]<<8 | alpha
}
