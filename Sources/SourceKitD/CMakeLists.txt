
add_library(SourceKitD STATIC
  SKDRequestArray.swift
  SKDRequestDictionary.swift
  SKDResponse.swift
  SKDResponseArray.swift
  SKDResponseDictionary.swift
  SourceKitD.swift
  SourceKitDImpl.swift
  SourceKitDRegistry.swift
  sourcekitd_functions.swift
  sourcekitd_uids.swift)
set_target_properties(SourceKitD PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SourceKitD PRIVATE
  Csourcekitd
  LSPLogging
  SKSupport
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
