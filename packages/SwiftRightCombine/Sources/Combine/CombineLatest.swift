import Foundation
import OpenCombine

// Apple: Publishers.CombineLatest(_:_:) / CombineLatest3 and Publisher.combineLatest(_:), combineLatest(_:_:), combineLatest(_:_:_:) (absent from OpenCombine 0.14).
// Semantics as Apple's: nothing is sent until every upstream has sent a value; then each new value sends the tuple of the latest values; finished when all
// upstreams finish; the first failure fails the whole and cancels the others. Demand: values are sent as they come (unlimited), which is what sink and assign request.

private final class LatestState<Failure: Error> {
    let lock = NSRecursiveLock()
    var values: [Any?]
    var finished: [Bool]
    var done = false
    var cancellables: [AnyCancellable] = []
    init(count: Int) { values = Array(repeating: nil, count: count); finished = Array(repeating: false, count: count) }
}

private final class LatestSubscription: Subscription {
    let cancelAll: () -> Void
    init(_ cancelAll: @escaping () -> Void) { self.cancelAll = cancelAll }
    func request(_ demand: Subscribers.Demand) {}
    func cancel() { cancelAll() }
}

private func combineLatestRun<Failure: Error, S: Subscriber>(_ subscribe: [(@escaping (Any) -> Void, @escaping (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable],
                                                            subscriber: S, make: @escaping ([Any]) -> S.Input) where S.Failure == Failure {
    let state = LatestState<Failure>(count: subscribe.count)
    subscriber.receive(subscription: LatestSubscription { state.lock.lock(); state.done = true; let c = state.cancellables; state.cancellables = []; state.lock.unlock(); c.forEach { $0.cancel() } })
    for (i, sub) in subscribe.enumerated() {
        let c = sub({ value in
            state.lock.lock()
            guard !state.done else { state.lock.unlock(); return }
            state.values[i] = value
            let all = state.values.compactMap { $0 }
            state.lock.unlock()
            if all.count == state.values.count { _ = subscriber.receive(make(all)) }
        }, { completion in
            state.lock.lock()
            guard !state.done else { state.lock.unlock(); return }
            switch completion {
            case .failure:
                state.done = true; let c = state.cancellables; state.lock.unlock()
                c.forEach { $0.cancel() }
                subscriber.receive(completion: completion)
            case .finished:
                state.finished[i] = true
                let allDone = !state.finished.contains(false)
                if allDone { state.done = true }
                state.lock.unlock()
                if allDone { subscriber.receive(completion: .finished) }
            }
        })
        state.lock.lock(); state.cancellables.append(c); state.lock.unlock()
    }
}

extension Publishers {
    /// Apple: https://developer.apple.com/documentation/combine/publishers/combinelatest
    public struct CombineLatest<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure {
        public typealias Output = (A.Output, B.Output)
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            combineLatestRun([{ v, c in a.sink(receiveCompletion: c, receiveValue: { v($0) }) }, { v, c in b.sink(receiveCompletion: c, receiveValue: { v($0) }) }],
                             subscriber: subscriber) { ($0[0] as! A.Output, $0[1] as! B.Output) }
        }
    }

    /// Apple: https://developer.apple.com/documentation/combine/publishers/combinelatest3
    public struct CombineLatest3<A: Publisher, B: Publisher, C: Publisher>: Publisher where A.Failure == B.Failure, B.Failure == C.Failure {
        public typealias Output = (A.Output, B.Output, C.Output)
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public let c: C
        public init(_ a: A, _ b: B, _ c: C) { self.a = a; self.b = b; self.c = c }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            combineLatestRun([{ v, k in a.sink(receiveCompletion: k, receiveValue: { v($0) }) }, { v, k in b.sink(receiveCompletion: k, receiveValue: { v($0) }) },
                              { v, k in c.sink(receiveCompletion: k, receiveValue: { v($0) }) }],
                             subscriber: subscriber) { ($0[0] as! A.Output, $0[1] as! B.Output, $0[2] as! C.Output) }
        }
    }
}

extension Publisher {
    public func combineLatest<P: Publisher>(_ other: P) -> Publishers.CombineLatest<Self, P> where P.Failure == Failure { Publishers.CombineLatest(self, other) }
    public func combineLatest<P: Publisher, T>(_ other: P, _ transform: @escaping (Output, P.Output) -> T) -> Publishers.Map<Publishers.CombineLatest<Self, P>, T>
        where P.Failure == Failure { Publishers.CombineLatest(self, other).map(transform) }
    public func combineLatest<P: Publisher, Q: Publisher>(_ p: P, _ q: Q) -> Publishers.CombineLatest3<Self, P, Q> where P.Failure == Failure, Q.Failure == Failure {
        Publishers.CombineLatest3(self, p, q)
    }
    public func combineLatest<P: Publisher, Q: Publisher, T>(_ p: P, _ q: Q, _ transform: @escaping (Output, P.Output, Q.Output) -> T)
        -> Publishers.Map<Publishers.CombineLatest3<Self, P, Q>, T> where P.Failure == Failure, Q.Failure == Failure {
        Publishers.CombineLatest3(self, p, q).map(transform)
    }
}
