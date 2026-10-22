import Foundation
import Dispatch
import OpenCombine
import OpenCombineDispatch

// Apple: DispatchQueue is a Scheduler itself (`receive(on: DispatchQueue.main)`). OpenCombine provides the scheduler as `queue.ocombine`; this conformance forwards
// to it; RunLoop likewise, and NotificationCenter.publisher(for:object:) forwards to `ocombine.publisher`. Timer.publish already has its Apple name on Windows.

extension DispatchQueue: OpenCombine.Scheduler {
    public typealias SchedulerTimeType = DispatchQueue.OCombine.SchedulerTimeType
    public typealias SchedulerOptions = DispatchQueue.OCombine.SchedulerOptions
    public var now: SchedulerTimeType { ocombine.now }
    public var minimumTolerance: SchedulerTimeType.Stride { ocombine.minimumTolerance }
    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) { ocombine.schedule(options: options, action) }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?, _ action: @escaping () -> Void) {
        ocombine.schedule(after: date, tolerance: tolerance, options: options, action)
    }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) -> Cancellable {
        ocombine.schedule(after: date, interval: interval, tolerance: tolerance, options: options, action)
    }
}

extension RunLoop: OpenCombine.Scheduler {
    public typealias SchedulerTimeType = RunLoop.OCombine.SchedulerTimeType
    public typealias SchedulerOptions = RunLoop.OCombine.SchedulerOptions
    public var now: SchedulerTimeType { ocombine.now }
    public var minimumTolerance: SchedulerTimeType.Stride { ocombine.minimumTolerance }
    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) { ocombine.schedule(options: options, action) }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?, _ action: @escaping () -> Void) {
        ocombine.schedule(after: date, tolerance: tolerance, options: options, action)
    }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) -> Cancellable {
        ocombine.schedule(after: date, interval: interval, tolerance: tolerance, options: options, action)
    }
}

extension NotificationCenter {
    /// Apple: https://developer.apple.com/documentation/foundation/notificationcenter/publisher(for:object:)
    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> NotificationCenter.OCombine.Publisher {
        ocombine.publisher(for: name, object: object)
    }
}
