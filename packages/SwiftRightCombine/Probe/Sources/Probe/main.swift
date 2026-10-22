// Written against Apple's Combine; must build and print the same on macOS (system Combine) and Windows (SwiftRightCombine).
import Foundation
import Combine

final class Model: ObservableObject {
    @Published var count = 0
    @Published var name = "a"
    @Published var derived = ""
    var bag = Set<AnyCancellable>()
    init() {
        $count.combineLatest($name).map { "\($0)-\($1)" }.assign(to: &$derived)
    }
}
let m = Model()
var log: [String] = []
var bag = Set<AnyCancellable>()
m.objectWillChange.sink { log.append("will") }.store(in: &bag)
m.$count.dropFirst().removeDuplicates().map { $0 * 2 }.sink { log.append("c2=\($0)") }.store(in: &bag)
Publishers.CombineLatest(m.$count, m.$name).sink { log.append("cl=\($0)/\($1)") }.store(in: &bag)
m.$count.combineLatest(m.$name, Just(true)).sink { log.append("cl3=\($0)\($1)\($2)") }.store(in: &bag)
let subject = PassthroughSubject<Int, Never>()
subject.receive(on: DispatchQueue.main).sink { log.append("main=\($0)") }.store(in: &bag)
subject.merge(with: Just(9)).collect(2).sink { log.append("merge=\($0)") }.store(in: &bag)
NotificationCenter.default.publisher(for: Notification.Name("X")).sink { _ in log.append("note") }.store(in: &bag)
m.count = 1; m.count = 1; m.name = "b"; subject.send(2)
NotificationCenter.default.post(name: Notification.Name("X"), object: nil)
var ticks = 0
let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { _ in ticks += 1 }
let deb = PassthroughSubject<Int, Never>()
deb.debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { log.append("deb=\($0)") }.store(in: &bag)
deb.send(1); deb.send(2)
let end = Date().addingTimeInterval(0.5)
while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
timer.cancel()
log.append("ticks>=5:\(ticks >= 5)")
log.append("derived=\(m.derived)")
print(log.joined(separator: " | "))
