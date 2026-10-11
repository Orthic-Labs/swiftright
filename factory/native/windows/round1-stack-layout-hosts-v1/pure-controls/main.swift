import Foundation
func require(_ condition: Bool) { if !condition { fatalError("pure fill control failed") } }
func reject(_ body: () throws -> Void) { do { try body(); fatalError("fault accepted") } catch {} }
let rectangle=try factoryFillRect(.rectangle,x:5,y:7,width:120,height:80)
require(rectangle == FactoryFillRect(x:5,y:7,width:120,height:80,radius:0))
let circle=try factoryFillRect(.circle,x:5,y:7,width:120,height:80)
require(circle == FactoryFillRect(x:25,y:7,width:80,height:80,radius:40))
let tall=try factoryFillRect(.circle,x:-5,y:10,width:30,height:70)
require(tall == FactoryFillRect(x:-5,y:30,width:30,height:30,radius:15))
require(try factorySemanticFill("system.red") == 0xff3b30ff)
require(try factorySemanticFill("system.blue") == 0x007affff)
require(try factoryRGBAFill([0.5,1,0,0.5],opacity:0.5) == 0x80ff0040)
require(try factoryRGBAFill([1,0,0,1],opacity:0) == 0xff000000)
reject { _=try factoryFillRect(.circle,x:0,y:0,width:-1,height:1) }
reject { _=try factoryFillRect(.rectangle,x:.nan,y:0,width:1,height:1) }
reject { _=try factorySemanticFill("invented-provider") }
reject { _=try factoryRGBAFill([1,0,0],opacity:1) }
reject { _=try factoryRGBAFill([1.1,0,0,1],opacity:1) }
reject { _=try factoryRGBAFill([1,0,0,1],opacity:.infinity) }
print("synthetic actual-shared-fill controls pass; nativecaptures0")
