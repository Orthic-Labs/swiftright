import Foundation
let outer=try FactoryScrollClip(x:10,y:20,width:100,height:80)
let first=try factoryInheritedScrollClip(nil,viewport:outer)
precondition(first==outer)
let inner=try FactoryScrollClip(x:50,y:0,width:100,height:60)
let intersection=try factoryInheritedScrollClip(outer,viewport:inner)
let expectedIntersection=try FactoryScrollClip(x:50,y:20,width:60,height:40)
precondition(intersection==expectedIntersection)
let empty=try factoryInheritedScrollClip(outer,viewport:FactoryScrollClip(x:200,y:200,width:10,height:10))
precondition(empty.width==0 && empty.height==0)
let nested=try factoryInheritedScrollClip(intersection,viewport:FactoryScrollClip(x:60,y:30,width:5,height:6))
let expectedNested=try FactoryScrollClip(x:60,y:30,width:5,height:6)
precondition(nested==expectedNested)
let offsetResolved=try FactoryScrollClip(x:-25,y:-15,width:200,height:100)
precondition(factoryScrollPaintBounds(offsetResolved)==offsetResolved)
for invalid in [(Float.nan,Float(1),Float(1),Float(1)),(0,0,-1,1),(Float.greatestFiniteMagnitude,0,Float.greatestFiniteMagnitude,1)] {
 var rejected=false
 do { _=try FactoryScrollClip(x:invalid.0,y:invalid.1,width:invalid.2,height:invalid.3) } catch { rejected=true }
 precondition(rejected)
}
print("FactoryScrollClip controls passed")
