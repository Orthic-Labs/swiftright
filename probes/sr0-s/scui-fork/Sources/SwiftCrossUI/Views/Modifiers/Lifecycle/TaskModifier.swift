extension View {
    /// Starts a task before a view appears (but after ``View/body`` has been
    /// accessed), and cancels the task when the view disappears. Additionally,
    /// if `id` changes the current task is cancelled and a new one is started.
    ///
    /// This variant of `task` can be useful when the lifetime of the task
    /// must be linked to a value with a potentially shorter lifetime than the
    /// view.
    ///
    /// - Parameters:
    ///   - id: The ID of the task.
    ///   - priority: The priority of the task.
    ///   - action: The action to perform within the task.
    public nonisolated func task<Id: Equatable>(
        id: Id,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping () async -> Void
    ) -> some View {
        TaskModifier(
            id: id,
            content: TupleView1(self),
            priority: priority,
            action: action
        )
    }

    /// Starts a task before a view appears (but after ``View/body`` has been
    /// accessed), and cancels the task when the view disappears.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - action: The action to perform within the task.
    public nonisolated func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping () async -> Void
    ) -> some View {
        TaskModifier(
            id: 0,
            content: TupleView1(self),
            priority: priority,
            action: action
        )
    }
}

struct TaskModifier<Id: Equatable, Content: View> {
    @State var task: Task<(), any Error>? = nil
    #if !SCUI_STOCK_TASKGUARD
    @State var owner: TaskOwner? = nil  // SR0-OVERRIDE O5
    #endif

    var id: Id
    var content: Content
    var priority: TaskPriority
    var action: () async -> Void
}

extension TaskModifier: View {
    var body: some View {
        #if !SCUI_STOCK_TASKGUARD
        // SR0-OVERRIDE O5: each run gets its own owner; restart and unmount invalidate it.
        content.onChange(of: id, initial: true) {
            task?.cancel()
            owner?.invalidate()
            let newOwner = TaskOwner()
            owner = newOwner
            task = Task(priority: priority) {
                await TaskOwner.$current.withValue(newOwner) {
                    await action()
                }
            }
        }.onDisappear {
            task?.cancel()
            owner?.invalidate()
        }
        #else
        content.onChange(of: id, initial: true) {
            task?.cancel()
            task = Task(priority: priority) {
                await action()
            }
        }.onDisappear {
            task?.cancel()
        }
        #endif
    }
}
