import Foundation
import OpenCombine

// Apple: Publishers.Merge / Merge3 / MergeMany and Publisher.merge(with:) (absent from OpenCombine 0.14). Values from every upstream are sent as they come; finished
// when all upstreams finish; the first failure fails the whole and cancels the others. Demand is unlimited (what sink and assign request).

private final class MergeSubscription: Subscription {
    let lock = NSRecursiveLock()
    var cancellables: [AnyCancellable] = []
    var done = false
    func request(_ demand: Subscribers.Demand) {}
    func cancel() {
        lock.lock(); done = true; let c = cancellables; cancellables = []; lock.unlock()
        c.forEach { $0.cancel() }
    }
}

private func mergeRun<Upstream: Publisher, S: Subscriber>(_ upstreams: [Upstream], _ subscriber: S) where S.Input == Upstream.Output, S.Failure == Upstream.Failure {
    let sub = MergeSubscription()
    subscriber.receive(subscription: sub)
    var remaining = upstreams.count
    if remaining == 0 { subscriber.receive(completion: .finished); return }
    for upstream in upstreams {
        let c = upstream.sink(receiveCompletion: { completion in
            sub.lock.lock()
            guard !sub.done else { sub.lock.unlock(); return }
            switch completion {
            case .failure:
                sub.done = true; let others = sub.cancellables; sub.lock.unlock()
                others.forEach { $0.cancel() }
                subscriber.receive(completion: completion)
            case .finished:
                remaining -= 1
                let all = remaining == 0
                if all { sub.done = true }
                sub.lock.unlock()
                if all { subscriber.receive(completion: .finished) }
            }
        }, receiveValue: { value in
            sub.lock.lock(); let done = sub.done; sub.lock.unlock()
            if !done { _ = subscriber.receive(value) }
        })
        sub.lock.lock(); sub.cancellables.append(c); sub.lock.unlock()
    }
}

extension Publishers {
    /// Apple: https://developer.apple.com/documentation/combine/publishers/merge
    public struct Merge<A: Publisher, B: Publisher>: Publisher where A.Output == B.Output, A.Failure == B.Failure {
        public typealias Output = A.Output
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            mergeRun([a.eraseToAnyPublisher(), b.eraseToAnyPublisher()], subscriber)
        }
    }

    /// Apple: https://developer.apple.com/documentation/combine/publishers/merge3
    public struct Merge3<A: Publisher, B: Publisher, C: Publisher>: Publisher where A.Output == B.Output, B.Output == C.Output, A.Failure == B.Failure, B.Failure == C.Failure {
        public typealias Output = A.Output
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public let c: C
        public init(_ a: A, _ b: B, _ c: C) { self.a = a; self.b = b; self.c = c }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            mergeRun([a.eraseToAnyPublisher(), b.eraseToAnyPublisher(), c.eraseToAnyPublisher()], subscriber)
        }
    }

    /// Apple: https://developer.apple.com/documentation/combine/publishers/mergemany
    public struct MergeMany<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let publishers: [Upstream]
        public init(_ upstream: Upstream...) { publishers = upstream }
        public init<S: Swift.Sequence>(_ upstream: S) where S.Element == Upstream { publishers = Array(upstream) }
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure { mergeRun(publishers, subscriber) }
    }
}

extension Publisher {
    public func merge<P: Publisher>(with other: P) -> Publishers.Merge<Self, P> where P.Output == Output, P.Failure == Failure { Publishers.Merge(self, other) }
    public func merge<B: Publisher, C: Publisher>(with b: B, _ c: C) -> Publishers.Merge3<Self, B, C>
        where B.Output == Output, B.Failure == Failure, C.Output == Output, C.Failure == Failure { Publishers.Merge3(self, b, c) }
}
