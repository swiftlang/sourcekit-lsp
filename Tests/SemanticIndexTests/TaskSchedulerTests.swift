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

import SKLogging
import SKTestSupport
import SemanticIndex
import XCTest

final class TaskSchedulerTests: XCTestCase {
  func testHighPriorityTasksGetExecutedBeforeLowPriorityTasks() async throws {
    let highPriorityTasks: Int = 4
    let lowPriorityTasks: Int = 2
    await runTaskScheduler(
      highPriorityTasks: highPriorityTasks,
      lowPriorityTasks: lowPriorityTasks,
      scheduleTasks: { scheduler, taskExecutionRecorder in
        for i in 0..<20 {
          let id = TaskID.lowPriority(i)
          await scheduler.schedule(priority: .low, id: id) {
            await taskExecutionRecorder.run(taskID: id)
          }
        }

        for i in 0..<10 {
          let id = TaskID.highPriority(i)
          await scheduler.schedule(priority: .high, id: id) {
            await taskExecutionRecorder.run(taskID: id)
          }
        }
      },
      validate: { (recordings: [Set<TaskID>]) in
        // Check that all high-priority tasks get executed before the low-priority tasks
        let highPriorityRecordingSlice = recordings.dropLast(while: {
          $0.isEmpty || $0.contains(where: \.isLowPriority)
        })
        assertAllSatisfy(highPriorityRecordingSlice) { !$0.contains(where: \.isLowPriority) }

        // Check that we never have more than the allowed number of low/high priority tasks, respectively
        assertAllSatisfy(recordings) { $0.count(where: \.isLowPriority) <= lowPriorityTasks }
        assertAllSatisfy(recordings) { $0.count <= highPriorityTasks }

        // Check that we do indeed use the maximum allowed parallelism.
        assertContains(recordings) { $0.count == highPriorityTasks }
      }
    )
  }

  func testTasksWithElevatedPrioritiesGetExecutedFirst() async throws {
    try SkipUnless.platformSupportsTaskPriorityElevation()
    await runTaskScheduler(
      scheduleTasks: { scheduler, taskExecutionRecorder in
        for i in 0..<20 {
          let id = TaskID.lowPriority(i)
          await scheduler.schedule(priority: .low, id: id) {
            await taskExecutionRecorder.run(taskID: id)
          }
        }

        var tasksToElevatePriorityFor: [Task<Void, Never>] = []
        for i in 0..<10 {
          let id = TaskID.highPriority(i)
          let task = await scheduler.schedule(priority: .low, id: id) {
            await taskExecutionRecorder.run(taskID: id)
          }
          tasksToElevatePriorityFor.append(task)
        }
        for task in tasksToElevatePriorityFor {
          Task(priority: .high) {
            await task.value
          }
        }
      },
      validate: { (recordings: [Set<TaskID>]) in
        // We might execute a few low-priority tasks before the high-priority tasks before the elevated priorities are
        // propagated to `QueuedTask`. Check that we have at least one low priority task executing after the last
        // high-priority task.
        let lastRecordingWithHighPriority = recordings.lastIndex(where: { $0.contains(where: \.isHighPriority) })
        guard let lastRecordingWithHighPriority else {
          XCTFail("Expected recordings that contain a high priority task")
          return
        }
        assertContains(recordings[lastRecordingWithHighPriority...]) { $0.contains(where: \.isLowPriority) }
      }
    )
  }

  func testDependencyDeclarationIsRespected() async {
    await runTaskScheduler(
      scheduleTasks: { scheduler, taskExecutionRecorder in
        for i in 0..<20 {
          let id = TaskID.lowPriority(i)
          await scheduler.schedule(
            priority: .low,
            id: id,
            body: { await taskExecutionRecorder.run(taskID: id) },
            dependencies: { currentlyExecutingTasks in
              return
                currentlyExecutingTasks
                .filter {
                  guard let taskId = $0.taskId else {
                    return false
                  }
                  return taskId.intValue.isMultiple(of: 2) == i.isMultiple(of: 2)
                }
                .map { .waitAndElevatePriorityOfDependency($0) }
            }
          )
        }
      },
      validate: { (recordings: [Set<TaskID>]) in
        for recording in recordings {
          // All even tasks depend on each other and all odd tasks depend on each other. So we should never execute them
          // simultaneously.
          XCTAssert(recording.count(where: { $0.intValue.isMultiple(of: 2) }) <= 1)
          XCTAssert(recording.count(where: { !$0.intValue.isMultiple(of: 2) }) <= 1)
        }
      }
    )
  }

  func testTaskSuspension() async {
    let suspendedTaskId = TaskID.highPriority(0)
    let suspenderTaskId = TaskID.highPriority(1)
    await runTaskScheduler(
      scheduleTasks: { scheduler, taskExecutionRecorder in
        await scheduler.schedule(
          priority: .high,
          id: suspendedTaskId,
          body: { await taskExecutionRecorder.run(taskID: suspendedTaskId, duration: .seconds(1)) },
          dependencies: { currentlyExecutingTasks in
            return
              currentlyExecutingTasks
              .filter { $0.taskId == suspenderTaskId }
              .map { .waitAndElevatePriorityOfDependency($0) }
          }
        )

        await scheduler.schedule(
          priority: .high,
          id: suspenderTaskId,
          body: { await taskExecutionRecorder.run(taskID: suspenderTaskId) },
          dependencies: { currentlyExecutingTasks in
            return
              currentlyExecutingTasks
              .filter { $0.taskId == suspendedTaskId }
              .map { .cancelAndRescheduleDependency($0) }
          }
        )
      },
      validate: { (recordings: [Set<TaskID>]) in
        let nonEmptyRecordings = recordings.filter({ !$0.isEmpty })
        // The suspended task might get cancelled to be rescheduled before or after we run the body. Allow either.
        XCTAssert(
          nonEmptyRecordings == [[suspendedTaskId], [suspenderTaskId], [suspendedTaskId]]
            || nonEmptyRecordings == [[suspenderTaskId], [suspendedTaskId]],
          "Recordings did not match expected: \(nonEmptyRecordings)"
        )
      }
    )
  }

  func testHighCPUCoreCountTaskBlocksExecutionOfMoreTasks() async {
    let highCPUCountTask = TaskID.highPriority(50)
    await runTaskScheduler(
      scheduleTasks: { scheduler, taskExecutionRecorder in
        for i in 1..<20 {
          let id = TaskID.highPriority(i)
          await scheduler.schedule(priority: .high, id: id) {
            await taskExecutionRecorder.run(taskID: id)
          }
        }

        await scheduler.schedule(priority: .high, id: highCPUCountTask, estimatedCPUCoreCount: 4) {
          await taskExecutionRecorder.run(taskID: highCPUCountTask)
        }

        for i in 1001..<1020 {
          let id = TaskID.highPriority(i)
          await scheduler.schedule(priority: .high, id: id) {
            await taskExecutionRecorder.run(taskID: id)
          }
        }
      },
      validate: { (recordings: [Set<TaskID>]) in
        for recording in recordings where recording.contains(highCPUCountTask) {
          assertNotContains(recording) { $0.intValue > 1000 }
        }
      }
    )
  }
}

// MARK: - Test helpers

/// Identifies a task that was scheduled in a test case.
fileprivate enum TaskID: Hashable, CustomDebugStringConvertible {
  case lowPriority(Int)
  case highPriority(Int)

  var isLowPriority: Bool {
    if case .lowPriority = self {
      return true
    }
    return false
  }

  var isHighPriority: Bool {
    if case .highPriority = self {
      return true
    }
    return false
  }

  var intValue: Int {
    switch self {
    case .lowPriority(let int): return int
    case .highPriority(let int): return int
    }
  }

  var debugDescription: String {
    switch self {
    case .lowPriority(let int):
      return "low(\(int))"
    case .highPriority(let int):
      return "high(\(int))"
    }
  }
}

/// A `TaskDescriptionProtocol` that is based on closures, which makes it easy to use in test cases.
fileprivate final class ClosureTaskDescription: TaskDescriptionProtocol {
  let taskId: TaskID?
  let estimatedCPUCoreCount: Int
  private let closure: @Sendable () async -> Void
  private let dependencies: @Sendable ([ClosureTaskDescription]) -> [TaskDependencyAction<ClosureTaskDescription>]
  var isIdempotent: Bool { true }
  var description: String { self.redactedDescription }
  var redactedDescription: String { taskId.debugDescription }

  init(
    id taskId: TaskID?,
    estimatedCPUCoreCount: Int = 1,
    _ closure: @Sendable @escaping () async -> Void,
    dependencies: @Sendable @escaping ([ClosureTaskDescription]) -> [TaskDependencyAction<ClosureTaskDescription>] = {
      _ in []
    }
  ) {
    self.taskId = taskId
    self.estimatedCPUCoreCount = estimatedCPUCoreCount
    self.closure = closure
    self.dependencies = dependencies
  }

  func execute() async {
    logger.debug("Starting execution of \(self) with priority \(Task.currentPriority.rawValue)")
    await closure()
    logger.debug("Finished executing \(self) with priority \(Task.currentPriority.rawValue)")
  }

  func dependencies(
    to currentlyExecutingTasks: [ClosureTaskDescription]
  ) -> [TaskDependencyAction<ClosureTaskDescription>] {
    return dependencies(currentlyExecutingTasks)
  }

}

/// Records the `TaskIDs` that were executed concurrently by `TaskScheduler`.
fileprivate actor TaskExecutionRecorder {
  private var executingTasksIds: Set<TaskID> = [] {
    didSet {
      taskRecordings.append(executingTasksIds)
    }
  }

  /// Every time a task starts or finishes, a new recording is added to this list, recording which tasks were executed
  /// concurrently.
  private(set) var taskRecordings: [Set<TaskID>] = []

  /// Record the given `taskID` as executing and wait for `duration` until we mark this task as being done.
  func run(taskID: TaskID, duration: Duration = .seconds(0.1)) async {
    executingTasksIds.insert(taskID)
    try? await Task.sleep(for: duration)
    executingTasksIds.remove(taskID)
  }
}

fileprivate func runTaskScheduler(
  highPriorityTasks: Int = 4,
  lowPriorityTasks: Int = 2,
  highPriorityThreshold: TaskPriority = .high,
  scheduleTasks: (TaskScheduler<ClosureTaskDescription>, TaskExecutionRecorder) async -> Void,
  validate: (_ recordings: [Set<TaskID>]) -> Void
) async {
  let scheduler = TaskScheduler<ClosureTaskDescription>(
    maxConcurrentTasksByPriority: [(.high, highPriorityTasks), (.low, lowPriorityTasks)]
  )
  let taskExecutionRecorder = TaskExecutionRecorder()

  let allTasksScheduled = WrappedSemaphore(name: "All tasks scheduled")

  // Keep scheduler busy so we can schedule all the remaining tasks that we actually want to test.
  // Using a semaphore here is an anti-pattern that should not be used in production since it can lead to priority
  // inversions. But since we know that `allTasksScheduled` will be signalled at a fairly high priority below and no
  // other tasks are running in the process other than the test, this is fine here.
  for _ in 0..<highPriorityTasks {
    await scheduler.schedule(priority: .high, id: nil) {
      allTasksScheduled.waitOrXCTFail()
    }
  }

  await scheduleTasks(scheduler, taskExecutionRecorder)
  allTasksScheduled.signal(value: highPriorityTasks)

  // Use a semaphore to wait for the scheduler to reach these very low-priority tasks.
  // Using utility for the priority ensures that these tasks get executed last and using a semaphore ensures that we
  // don't elevate the task's priority by awaiting it.
  let reachedEnd = WrappedSemaphore(name: "Reached end")
  await scheduler.schedule(
    priority: TaskPriority.low,
    id: nil,
    body: { reachedEnd.signal() },
    dependencies: { currentlyExecutingTasks in
      return currentlyExecutingTasks.map { .waitAndElevatePriorityOfDependency($0) }
    }
  )
  reachedEnd.waitOrXCTFail()

  let recordings = await taskExecutionRecorder.taskRecordings
  validate(recordings)
}

fileprivate extension TaskScheduler<ClosureTaskDescription> {
  @discardableResult
  func schedule(
    priority: TaskPriority? = nil,
    id: TaskID?,
    estimatedCPUCoreCount: Int = 1,
    body: @Sendable @escaping () async -> Void,
    dependencies: @Sendable @escaping ([ClosureTaskDescription]) -> [TaskDependencyAction<ClosureTaskDescription>] = {
      _ in []
    }
  ) async -> Task<Void, Never> {
    let taskDescription = ClosureTaskDescription(
      id: id,
      estimatedCPUCoreCount: estimatedCPUCoreCount,
      body,
      dependencies: dependencies
    )
    // Make sure that we call `schedule` outside of the `Task` because the execution order of `Task`s is not guaranteed
    // and if we called `schedule` inside `Task`, Swift concurrency can re-order the order that we schedule tasks in.
    let queuedTask = await self.schedule(priority: priority, taskDescription)
    return Task(priority: priority) {
      await queuedTask.waitToFinishPropagatingCancellation()
    }
  }
}

// MARK: - Misc assertion functions

fileprivate func assertAllSatisfy<Element>(
  _ array: some Collection<Element>,
  _ predicate: (Element) -> Bool,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssert(array.allSatisfy(predicate), "\(array) did not fulfill predicate", file: file, line: line)
}

fileprivate func assertContains<Element>(
  _ array: some Collection<Element>,
  _ predicate: (Element) -> Bool,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssert(array.contains(where: predicate), "\(array) did not fulfill predicate", file: file, line: line)
}

fileprivate func assertNotContains<Element>(
  _ array: some Collection<Element>,
  _ predicate: (Element) -> Bool,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssert(!array.contains(where: predicate), "\(array) did not fulfill predicate", file: file, line: line)
}

// MARK: - Collection utilities

fileprivate extension Collection {
  func dropLast(while predicate: (Element) -> Bool) -> [Element] {
    return Array(self.reversed().drop(while: predicate).reversed())
  }

  func count(where predicate: (Element) -> Bool) -> Int {
    return self.filter(predicate).count
  }
}
