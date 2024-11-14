
add_library(SwiftExtensions STATIC
  Array+Safe.swift
  AsyncQueue.swift
  AsyncUtils.swift
  Atomics.swift
  Cache.swift
  CartesianProduct.swift
  Collection+Only.swift
  Collection+PartitionIntoBatches.swift
  Duration+Seconds.swift
  FileManagerExtensions.swift
  NSLock+WithLock.swift
  PipeAsStringHandler.swift
  ResultExtensions.swift
  Sequence+AsyncMap.swift
  Sequence+ContainsAnyIn.swift
  Task+WithPriorityChangedHandler.swift
  ThreadSafeBox.swift
  TransitiveClosure.swift
  URLExtensions.swift
)
set_target_properties(SwiftExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(SwiftExtensions PUBLIC
  CAtomics)

target_link_libraries(SwiftExtensions PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
