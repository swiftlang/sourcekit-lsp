set(sources
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
  LazyValue.swift
  NSLock+WithLock.swift
  PipeAsStringHandler.swift
  Platform.swift
  Process+terminate.swift
  ResultExtensions.swift
  Sequence+AsyncMap.swift
  Sequence+ContainsAnyIn.swift
  Task+WithPriorityChangedHandler.swift
  ThreadSafeBox.swift
  TransitiveClosure.swift
  URLExtensions.swift
)

add_library(SwiftExtensions STATIC ${sources})
set_target_properties(SwiftExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SwiftExtensions PUBLIC
  CAtomics)
target_link_libraries(SwiftExtensions PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

add_library(SwiftExtensionsForPlugin STATIC ${sources})
set_target_properties(SwiftExtensionsForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SwiftExtensionsForPlugin PUBLIC
  CAtomics)
target_link_libraries(SwiftExtensionsForPlugin PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
