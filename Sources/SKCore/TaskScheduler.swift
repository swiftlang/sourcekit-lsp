//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CAtomics
import Foundation
import LSPLogging

/// See comment on ``TaskDescriptionProtocol/dependencies(to:taskPriority:)``
public enum TaskDependencyAction<TaskDescription: TaskDescriptionProtocol> {
  case waitAndElevatePriorityOfDependency(TaskDescription)
  case cancelAndRescheduleDependency(TaskDescription)
}

public protocol TaskDescriptionProtocol: Identifiable, Sendable, CustomLogStringConvertible {
  /// Execute the task.
  ///
  ///  - Important: This should only be called from `TaskScheduler` and never be called manually.
  func execute() async

  /// When a new task is picked for execution, this determines how the task should behave with respect to the tasks that
  /// are already running.
  ///
  /// Options are the following (see doc comment on `TaskScheduler` for examples):
  ///  1. Not add any `TaskDependencyAction` for a currently executing task. This means that the two tasks can run in
  ///     parallel.
  ///  2. Declare a `waitAndElevatePriorityOfDependency` dependency. This will prevent execution of this task until
  ///     the other task has finished executing. It will elevate the priority of the dependency to the same priority as
  ///     this task. This ensures that we don't get into a priority inversion problem where a high-priority task is
  ///     waiting for a low-priority task.
  ///  3. Declare a `cancelAndRescheduleDependency`. If the task dependency is idempotent and has a priority that's not
  ///     higher than the this task's priority, this causes the task dependency to be cancelled, so that this task can
  ///     execute. The canceled task will be scheduled to re-run at a later point.
  ///     - Declaring a `cancelAndRescheduleDependency` dependency on a task that is not idempotent will change the
  ///       dependency to a `waitAndElevatePriorityOfDependency` dependency and log a fault.
  ///       A `cancelAndRescheduleDependency` dependency should never be emitted for a task that's not idempotent.
  ///     - If the task that should be canceled and re-scheduled has a higher priority than this task, the
  ///       `waitAndElevatePriorityOfDependency` dependency is changed to a `waitAndElevatePriorityOfDependency`
  ///       dependency. This is done to ensure that low-priority tasks can't interfere with the execution of
  ///       high-priority tasks.
  ///     - **Important**: The task that is canceled to be rescheduled must depend on this task, otherwise the two tasks
  ///       will fight each other for execution priority.
  func dependencies(to currentlyExecutingTasks: [Self]) -> [TaskDependencyAction<Self>]

  /// Whether executing this task twice produces the same results.
  ///
  /// This is required for the task to be canceled and re-scheduled (`TaskDependencyAction.cancelAndRescheduleDependency`)
  ///
  /// Tasks that are not idempotent should never be cancelled and rescheduled in the first place. This variable is just
  /// a safety net in case non-idempotent tasks are cancelled and rescheduled. It also ensures that tasks conforming to
  /// `TaskDescriptionProtocol` think about idempotency.
  var isIdempotent: Bool { get }

  /// The number of CPU cores this task is expected to use.
  ///
  /// If the `TaskScheduler` only allows 4 concurrent tasks and a task has `estimatedCPUCoreCount == 4`, this means that
  /// no other tasks will be scheduled while this task is executing. Note that the `TaskScheduler` might over-subscribe
  /// itself to start executing this task though, ie. it only needs to have one available execution slot even if this
  /// task will use 4 CPU cores. This ensures that we get to schedule a 4-core high-priority task in a 4 core scheduler
  /// if there are 100 low-priority 1-core tasks in the queue. Otherwise we would just keep executing those whenever a
  /// slot opens up and only have enough available slots to execute the 4-core high-priority task when all the
  /// low-priority tasks are done.
  ///
  /// For example, this is used by preparation tasks that are known to prepare multiple targets (or source files within
  /// one target) in parallel.
  var estimatedCPUCoreCount: Int { get }
}

/// Parameter that's passed to `executionStateChangedCallback` to indicate the new state of a scheduled task.
public enum TaskExecutionState {
  /// The task started executing.
  case executing

  /// The task was cancelled and will be re-scheduled for execution later. Will be followed by another call with
  /// `executing`.
  case cancelledToBeRescheduled

  /// The task has finished executing. Now more state updates will come after this one.
  case finished
}

public actor QueuedTask<TaskDescription: TaskDescriptionProtocol> {
  /// Result of `executionTask` / the tasks in `executionTaskCreatedContinuation`.
  /// See doc comment on `executionTask`.
  enum ExecutionTaskFinishStatus {
    case terminated
    case cancelledToBeRescheduled
  }

  /// The `TaskDescription` that defines what the queued task does.
  ///
  /// This is also used to determine dependencies between running tasks.
  nonisolated let description: TaskDescription

  /// The `Task` that produces the actual result of the `QueuedTask`. This is the task that is visible to clients.
  ///
  /// See initialization of this task to see how it works.
  ///
  /// - Note: Implicitly unwrapped optional so the task's closure can access `self`.
  /// - Note: `nonisolated(unsafe)` is fine because it will never get modified after being set in the initializer.
  nonisolated(unsafe) private(set) var resultTask: Task<Void, Never>! = nil

  /// After `execute` is called, the `executionTask` is a task that performs the computation defined by
  /// `description.execute`.
  ///
  /// The `resultTask` effectively waits for this task to be set (by watching for new values produced by
  /// `executionTaskCreatedContinuation`) and awaits its result. The task can terminate with two different statuses:
  ///  - `terminated`: The task has finished executing and the `resultTask` is done.
  ///  - `cancelledToBeRescheduled`: The `executionTask` was cancelled by calling `QueuedTask.cancelToBeRescheduled()`.
  ///    In this case the `TaskScheduler` is expected to call `execute` again, which will produce a new
  ///    `executionTask`. `resultTask` then awaits the creation of the new `executionTask` and then the result of that
  ///    `executionTask`.
  private var executionTask: Task<ExecutionTaskFinishStatus, Never>?

  /// Every time `execute` gets called, a new task is placed in this continuation. See comment on `executionTask`.
  private let executionTaskCreatedContinuation: AsyncStream<Task<ExecutionTaskFinishStatus, Never>>.Continuation

  /// Placing a new value in this continuation will cause `resultTask` to query its priority and set
  /// `QueuedTask.priority`.
  private let updatePriorityContinuation: AsyncStream<Void>.Continuation

  nonisolated(unsafe) private var _priority: AtomicUInt8

  /// The latest known priority of the task.
  ///
  /// This starts off as the priority with which the task is being created. If higher priority tasks start depending on
  /// it, the priority may get elevated.
  nonisolated var priority: TaskPriority {
    get {
      TaskPriority(rawValue: _priority.value)
    }
    set {
      _priority.value = newValue.rawValue
    }
  }

  /// Whether `cancelToBeRescheduled` has been called on this `QueuedTask`.
  ///
  /// Gets reset every time `executionTask` finishes.
  nonisolated(unsafe) private var cancelledToBeRescheduled: AtomicBool = .init(initialValue: false)

  /// Whether `resultTask` has been cancelled.
  private nonisolated(unsafe) var resultTaskCancelled: AtomicBool = .init(initialValue: false)

  private nonisolated(unsafe) var _isExecuting: AtomicBool = .init(initialValue: false)

  /// Whether the task is currently executing or still queued to be executed later.
  public nonisolated var isExecuting: Bool {
    return _isExecuting.value
  }

  public nonisolated func cancel() {
    resultTask.cancel()
  }

  /// Wait for the task to finish.
  ///
  /// If the tasks that waits for this queued task to finished is cancelled, the QueuedTask will still continue
  /// executing.
  public func waitToFinish() async {
    return await resultTask.value
  }

  /// Wait for the task to finish.
  ///
  /// If the tasks that waits for this queued task to finished is cancelled, the QueuedTask will also be cancelled.
  /// This assumes that the caller of this method has unique control over the task and is the only one interested in its
  /// value.
  public func waitToFinishPropagatingCancellation() async {
    return await resultTask.valuePropagatingCancellation
  }

  /// A callback that will be called when the task starts executing, is cancelled to be rescheduled, or when it finishes
  /// execution.
  private let executionStateChangedCallback: (@Sendable (QueuedTask, TaskExecutionState) async -> Void)?

  init(
    priority: TaskPriority? = nil,
    description: TaskDescription,
    executionStateChangedCallback: (@Sendable (QueuedTask, TaskExecutionState) async -> Void)?
  ) async {
    self._priority = .init(initialValue: priority?.rawValue ?? Task.currentPriority.rawValue)
    self.description = description
    self.executionStateChangedCallback = executionStateChangedCallback

    var updatePriorityContinuation: AsyncStream<Void>.Continuation!
    let updatePriorityStream = AsyncStream {
      updatePriorityContinuation = $0
    }
    self.updatePriorityContinuation = updatePriorityContinuation

    var executionTaskCreatedContinuation: AsyncStream<Task<ExecutionTaskFinishStatus, Never>>.Continuation!
    let executionTaskCreatedStream = AsyncStream {
      executionTaskCreatedContinuation = $0
    }
    self.executionTaskCreatedContinuation = executionTaskCreatedContinuation

    self.resultTask = Task.detached(priority: priority) {
      await withTaskCancellationHandler {
        await withTaskGroup(of: Void.self) { taskGroup in
          taskGroup.addTask {
            for await _ in updatePriorityStream {
              self.priority = Task.currentPriority
            }
          }
          taskGroup.addTask {
            for await task in executionTaskCreatedStream {
              switch await task.valuePropagatingCancellation {
              case .cancelledToBeRescheduled:
                // Break the switch and wait for a new `executionTask` to be placed into `executionTaskCreatedStream`.
                break
              case .terminated:
                // The task finished. We are done with this `QueuedTask`
                return
              }
            }
          }
          // The first (update priority) task never finishes, so this waits for the second (wait for execution) task
          // to terminate.
          // Afterwards we also cancel the update priority task.
          for await _ in taskGroup {
            taskGroup.cancelAll()
            return
          }
        }
      } onCancel: {
        self.resultTaskCancelled.value = true
      }
    }
  }

  /// Start executing the task.
  ///
  /// Execution might be canceled to be rescheduled, in which case this returns  `.cancelledToBeRescheduled`. In that
  /// case the `TaskScheduler` is expected to call `execute` again.
  func execute() async -> ExecutionTaskFinishStatus {
    precondition(executionTask == nil, "Task started twice")
    let task = Task.detached(priority: self.priority) {
      if !Task.isCancelled && !self.resultTaskCancelled.value {
        await self.description.execute()
      }
      return await self.finalizeExecution()
    }
    executionTask = task
    executionTaskCreatedContinuation.yield(task)
    _isExecuting.value = true
    await executionStateChangedCallback?(self, .executing)
    return await task.value
  }

  /// Implementation detail of `execute` that is called after `self.description.execute()` finishes.
  private func finalizeExecution() async -> ExecutionTaskFinishStatus {
    self.executionTask = nil
    _isExecuting.value = false
    if Task.isCancelled && self.cancelledToBeRescheduled.value {
      await executionStateChangedCallback?(self, .cancelledToBeRescheduled)
      self.cancelledToBeRescheduled.value = false
      return ExecutionTaskFinishStatus.cancelledToBeRescheduled
    } else {
      await executionStateChangedCallback?(self, .finished)
      return ExecutionTaskFinishStatus.terminated
    }
  }

  /// Cancel the task to be rescheduled later.
  ///
  /// If the task has not been started yet or has already finished execution, this is a no-op.
  func cancelToBeRescheduled() {
    guard let executionTask else {
      return
    }
    self.cancelledToBeRescheduled.value = true
    executionTask.cancel()
    self.executionTask = nil
  }

  /// Trigger `QueuedTask.priority` to be updated with the current priority of the underlying task.
  ///
  /// This is an asynchronous operation that makes no guarantees when the updated priority will be available.
  ///
  /// This is needed because tasks can't subscribe to priority updates (ie. there is no `withPriorityHandler` similar to
  /// `withCancellationHandler`, https://github.com/apple/swift/issues/73367).
  func triggerPriorityUpdate() {
    updatePriorityContinuation.yield()
  }

  /// If the priority of this task is less than `targetPriority`, elevate the priority to `targetPriority` by spawning
  /// a new task that depends on it. Otherwise a no-op.
  nonisolated func elevatePriority(to targetPriority: TaskPriority) {
    if priority < targetPriority {
      Task(priority: targetPriority) {
        await self.resultTask.value
      }
    }
  }
}

/// Schedules an unordered list of tasks for execution.
///
/// The key features that `TaskScheduler` provides are:
///  - It allows the dynamic declaration of dependencies between tasks. A task can declare whether it can be executed
///    based on which other tasks are currently running. For example, this allows us to guarantee that only a single
///    preparation task is running at a time without enforcing any order in which the preparation tasks should run.
///  - It allows the maximum number of tasks to be limited at a given priority. This allows us to eg. only use half the
///    computer's cores for background indexing and using all cores if user interaction is depending on a set of files
///    being indexed without over-subscribing the CPU.
///  - It allows tasks to be canceled and rescheduled to make room for tasks that are faster to execute. For example,
///    this is used when we have a joint background index task for file `A`, `B` and `C` (which might be in the same
///    target) with low priority. We now request to index `A` with high priority separately because it's needed for user
///    interaction. This cancels the joint indexing of `A`, `B` and `C` so that `A` can be indexed as a standalone file
///    as quickly as possible. The joint indexing of `A`, `B` and `C` is then re-scheduled (again at low priority) and
///    will depend on `A` being indexed.
public actor TaskScheduler<TaskDescription: TaskDescriptionProtocol> {
  /// The tasks that are currently being executed.
  ///
  /// All tasks in this queue are guaranteed to trigger a call `poke` again once they finish. Thus, whenever there are
  /// items left in this array, we are guaranteed to get another call to `poke`
  private var currentlyExecutingTasks: [QueuedTask<TaskDescription>] = []

  /// The queue of pending tasks that haven't been scheduled for execution yet.
  private var pendingTasks: [QueuedTask<TaskDescription>] = []

  /// An ordered list of task priorities to the number of tasks that might execute concurrently at that (or a higher)
  /// priority.
  ///
  /// This list is sorted in descending priority order.
  ///
  /// The `maxConcurrentTasks` of the last element in this list is also used for tasks with a lower priority.
  ///
  /// For example if you have
  /// ```swift
  /// [
  ///   (.medium, 4),
  ///   (.low, 2)
  /// ]
  /// ```
  ///
  /// Then we allow the following number of concurrent tasks at the following priorities
  ///  - `.high`: 4
  ///  - `.medium`: 4
  ///  - `.low`: 2
  ///  - `.background`: 2
  private let maxConcurrentTasksByPriority: [(priority: TaskPriority, maxConcurrentTasks: Int)]

  public init(maxConcurrentTasksByPriority: [(priority: TaskPriority, maxConcurrentTasks: Int)]) {
    self.maxConcurrentTasksByPriority = maxConcurrentTasksByPriority.sorted(by: { $0.priority > $1.priority })
    precondition(maxConcurrentTasksByPriority.map(\.maxConcurrentTasks).isSorted(descending: true))
    precondition(!maxConcurrentTasksByPriority.isEmpty)
    precondition(maxConcurrentTasksByPriority.last!.maxConcurrentTasks >= 1)
  }

  /// Enqueue a new task to be executed.
  ///
  /// - Important: A task that is scheduled by `TaskScheduler` must never be awaited from a task that runs on
  ///   `TaskScheduler`. Otherwise we might end up in deadlocks, eg. if the inner task cannot be scheduled because the
  ///   outer task is claiming all execution slots in the `TaskScheduler`.
  @discardableResult
  public func schedule(
    priority: TaskPriority? = nil,
    _ taskDescription: TaskDescription,
    @_inheritActorContext executionStateChangedCallback: (
      @Sendable (QueuedTask<TaskDescription>, TaskExecutionState) async -> Void
    )? = nil
  ) async -> QueuedTask<TaskDescription> {
    let queuedTask = await QueuedTask(
      priority: priority,
      description: taskDescription,
      executionStateChangedCallback: executionStateChangedCallback
    )
    pendingTasks.append(queuedTask)
    Task.detached(priority: priority ?? Task.currentPriority) {
      // Poke the `TaskScheduler` to execute a new task. If the `TaskScheduler` is already working at its capacity
      // limit, this will not do anything. If there are execution slots available, this will start executing the freshly
      // queued task.
      await self.poke()
    }
    return queuedTask
  }

  /// Trigger all queued tasks to update their priority.
  ///
  /// Should be called occasionally to elevate tasks in the queue whose underlying `Swift.Task` had their priority
  /// elevated because a higher-priority task started depending on them.
  private func triggerPriorityUpdateOfQueuedTasks() async {
    for task in pendingTasks {
      await task.triggerPriorityUpdate()
    }
  }

  /// Returns the maximum number of concurrent tasks that are allowed to execute at the given priority.
  private func maxConcurrentTasks(at priority: TaskPriority) -> Int {
    for (atPriority, maxConcurrentTasks) in maxConcurrentTasksByPriority {
      if atPriority <= priority {
        return maxConcurrentTasks
      }
    }
    // `last!` is fine because the initializer of `maxConcurrentTasksByPriority` has a precondition that
    // `maxConcurrentTasksByPriority` is not empty.
    return maxConcurrentTasksByPriority.last!.maxConcurrentTasks
  }

  /// Poke the execution of more tasks in the queue.
  ///
  /// This will continue calling itself until the queue is empty.
  private func poke() {
    pendingTasks.sort(by: { $0.priority > $1.priority })
    for task in pendingTasks {
      if currentlyExecutingTasks.map(\.description.estimatedCPUCoreCount).sum() >= maxConcurrentTasks(at: task.priority)
      {
        // We don't have any execution slots left. Thus, this poker has nothing to do and is done.
        // When the next task finishes, it calls `poke` again.
        // If the low priority task's priority gets elevated, that will be picked up when the next task in the
        // `TaskScheduler` finishes, which causes  `triggerPriorityUpdateOfQueuedTasks` to be called, which transfers
        // the new elevated priority to `QueuedTask.priority` and which can then be picked up by the next `poke` call.
        return
      }
      let dependencies = task.description.dependencies(to: currentlyExecutingTasks.map(\.description))
      let waitForTasks = dependencies.compactMap { (taskDependency) -> QueuedTask<TaskDescription>? in
        switch taskDependency {
        case .cancelAndRescheduleDependency(let taskDescription):
          guard let dependency = self.currentlyExecutingTasks.first(where: { $0.description.id == taskDescription.id })
          else {
            logger.fault(
              "Cannot find task to wait for \(taskDescription.forLogging) in list of currently executing tasks"
            )
            return nil
          }
          if !taskDescription.isIdempotent {
            logger.fault("Cannot reschedule task '\(taskDescription.forLogging)' since it is not idempotent")
            return dependency
          }
          if dependency.priority > task.priority {
            // Don't reschedule tasks that are more important than the new task we would like to schedule.
            return dependency
          }
          return nil
        case .waitAndElevatePriorityOfDependency(let taskDescription):
          guard let dependency = self.currentlyExecutingTasks.first(where: { $0.description.id == taskDescription.id })
          else {
            logger.fault(
              "Cannot find task to wait for '\(taskDescription.forLogging)' in list of currently executing tasks"
            )
            return nil
          }
          return dependency
        }
      }
      if !waitForTasks.isEmpty {
        // This task is blocked by a task that's currently executing. Elevate the priorities of those tasks and continue
        // looking in the queue if there is another task we can execute.
        for waitForTask in waitForTasks {
          waitForTask.elevatePriority(to: task.priority)
        }
        continue
      }
      let rescheduleTasks = dependencies.compactMap { (taskDependency) -> QueuedTask<TaskDescription>? in
        switch taskDependency {
        case .cancelAndRescheduleDependency(let taskDescription):
          guard let task = self.currentlyExecutingTasks.first(where: { $0.description.id == taskDescription.id }) else {
            logger.fault(
              "Cannot find task to reschedule \(taskDescription.forLogging) in list of currently executing tasks"
            )
            return nil
          }
          return task
        default:
          return nil
        }
      }
      if !rescheduleTasks.isEmpty {
        Task.detached(priority: task.priority) {
          for task in rescheduleTasks {
            await task.cancelToBeRescheduled()
          }
        }
        // Don't go looking for other tasks to execute in this poker because we should be waiting for the rescheduled
        // tasks to finish (which will call `poke` again), and then actually schedule `task`.
        // If we did enqueue another task from the pending queue, that new task might introduce a new dependency `task`,
        // which could delay its execution and render the suspension of previous tasks useless.
        return
      }

      currentlyExecutingTasks.append(task)
      pendingTasks.removeAll(where: { $0 === task })
      Task.detached(priority: task.priority) {
        // Await the task's return in a task so that this poker can continue checking if there are more execution
        // slots that can be filled with queued tasks.
        let finishStatus = await task.execute()
        await self.finalizeTaskExecution(task: task, finishStatus: finishStatus)
      }
    }
  }

  /// Implementation detail of `poke` to be called after `task.execute()` to ensure that `task.execute()` executes in
  /// a different isolation domain then `TaskScheduler`.
  private func finalizeTaskExecution(
    task: QueuedTask<TaskDescription>,
    finishStatus: QueuedTask<TaskDescription>.ExecutionTaskFinishStatus
  ) async {
    currentlyExecutingTasks.removeAll(where: { $0.description.id == task.description.id })
    switch finishStatus {
    case .terminated: break
    case .cancelledToBeRescheduled: pendingTasks.append(task)
    }
    await self.triggerPriorityUpdateOfQueuedTasks()
    self.poke()
  }
}

extension TaskScheduler {
  @_spi(Testing)
  public static var forTesting: TaskScheduler {
    return .init(maxConcurrentTasksByPriority: [
      (.low, ProcessInfo.processInfo.processorCount)
    ])
  }
}

// MARK: - Collection utilities

fileprivate extension Collection where Element: Comparable {
  func isSorted(descending: Bool) -> Bool {
    var previous = self.first
    for element in self {
      if (previous! < element) == descending {
        return false
      }
      previous = element
    }
    return true
  }
}

fileprivate extension Collection<Int> {
  func sum() -> Int {
    var result = 0
    for element in self {
      result += element
    }
    return result
  }
}
