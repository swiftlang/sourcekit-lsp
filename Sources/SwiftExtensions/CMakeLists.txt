set(sources
  Array+Safe.swift
  Array+SortAndDedupe.swift
  Cache.swift
  CartesianProduct.swift
  Collection+DropLast.swift
  Collection+PartitionIntoBatches.swift
  DisableSigpipe.swift
  LazyValue.swift
  Platform.swift
  Process+terminate.swift
  ResultExtensions.swift
  RunWithCleanup.swift
  Sequence+AsyncMap.swift
  Sequence+ContainsAnyIn.swift
  TransitiveClosure.swift
)

add_library(SwiftExtensions STATIC ${sources})
set_target_properties(SwiftExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SwiftExtensions PUBLIC
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions)
target_link_libraries(SwiftExtensions PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

add_library(SwiftExtensionsForPlugin STATIC ${sources})
set_target_properties(SwiftExtensionsForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SwiftExtensionsForPlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
target_link_libraries(SwiftExtensionsForPlugin PUBLIC
  SwiftToolsProtocols::_ToolsProtocolsSwiftExtensionsForPlugin)
target_link_libraries(SwiftExtensionsForPlugin PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
