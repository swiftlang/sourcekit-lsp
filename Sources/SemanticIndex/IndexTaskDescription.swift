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

/// Protocol of tasks that are executed on the index task scheduler.
///
/// It is assumed that `IndexTaskDescription` of different types are allowed to execute in parallel.
protocol IndexTaskDescription: TaskDescriptionProtocol {
  /// A string that is unique to this type of `IndexTaskDescription`. It is used to produce unique IDs for tasks of
  /// different types in `AnyIndexTaskDescription`
  static var idPrefix: String { get }

  var id: UInt32 { get }
}

extension IndexTaskDescription {
  func dependencies(
    to currentlyExecutingTasks: [AnyIndexTaskDescription]
  ) -> [TaskDependencyAction<AnyIndexTaskDescription>] {
    return self.dependencies(to: currentlyExecutingTasks.compactMap { $0.wrapped as? Self })
      .map {
        switch $0 {
        case .cancelAndRescheduleDependency(let td):
          return .cancelAndRescheduleDependency(AnyIndexTaskDescription(td))
        case .waitAndElevatePriorityOfDependency(let td):
          return .waitAndElevatePriorityOfDependency(AnyIndexTaskDescription(td))
        }
      }

  }
}

/// Type-erased wrapper of an `IndexTaskDescription`.
package struct AnyIndexTaskDescription: TaskDescriptionProtocol {
  let wrapped: any IndexTaskDescription

  init(_ wrapped: any IndexTaskDescription) {
    self.wrapped = wrapped
  }

  package var isIdempotent: Bool {
    return wrapped.isIdempotent
  }

  package var estimatedCPUCoreCount: Int {
    return wrapped.estimatedCPUCoreCount
  }

  package var id: String {
    return "\(type(of: wrapped).idPrefix)-\(wrapped.id)"
  }

  package var description: String {
    return wrapped.description
  }

  package var redactedDescription: String {
    return wrapped.redactedDescription
  }

  package func execute() async {
    return await wrapped.execute()
  }

  /// Forward to the underlying task to compute the dependencies. Preparation and index tasks don't have any
  /// dependencies that are managed by `TaskScheduler`. `SemanticIndexManager` awaits the preparation of a target before
  /// indexing files within it.
  package func dependencies(
    to currentlyExecutingTasks: [AnyIndexTaskDescription]
  ) -> [TaskDependencyAction<AnyIndexTaskDescription>] {
    return wrapped.dependencies(to: currentlyExecutingTasks)
  }
}
