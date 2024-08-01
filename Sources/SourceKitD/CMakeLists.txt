
add_library(SourceKitD STATIC
  dlopen.swift
  SKDRequestArray.swift
  SKDRequestDictionary.swift
  SKDResponse.swift
  SKDResponseArray.swift
  SKDResponseDictionary.swift
  SourceKitD.swift
  DynamicallyLoadedSourceKitD.swift
  SourceKitDRegistry.swift
  sourcekitd_functions.swift
  sourcekitd_uids.swift)
set_target_properties(SourceKitD PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SourceKitD PUBLIC
  Csourcekitd)
target_link_libraries(SourceKitD PRIVATE
  SKLogging
  SKSupport
  SwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
