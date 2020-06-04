if(CMAKE_VERSION VERSION_LESS 3.16)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
    set(CMAKE_LINK_LIBRARY_SUFFIX "")
  endif()
endif()

add_library(SourceKit
  DocumentManager.swift
  IndexStoreDB+MainFilesProvider.swift
  SourceKitIndexDelegate.swift
  SourceKitLSPCommandMetadata.swift
  SourceKitServer+Options.swift
  SourceKitServer.swift
  ToolchainLanguageServer.swift
  Workspace.swift)
target_sources(SourceKit PRIVATE
  Clang/ClangLanguageServer.swift)
target_sources(SourceKit PRIVATE
  Swift/CommentXML.swift
  Swift/CursorInfo.swift
  Swift/Diagnostic.swift
  Swift/EditorPlaceholder.swift
  Swift/SemanticRefactorCommand.swift
  Swift/SemanticRefactoring.swift
  Swift/SourceKitD+ResponseError.swift
  Swift/SwiftCommand.swift
  Swift/SwiftLanguageServer.swift)
set_target_properties(SourceKit PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
# TODO(compnerd) reduce the exposure here, why is everything PUBLIC-ly linked?
target_link_libraries(SourceKit PUBLIC
  Csourcekitd
  BuildServerProtocol
  IndexStoreDB
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKCore
  SKSwiftPMWorkspace
  SourceKitD
  TSCUtility)

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS SourceKit
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:SourceKit,Swift_MODULE_DIRECTORY>/SourceKit.swiftdoc
    $<TARGET_PROPERTY:SourceKit,Swift_MODULE_DIRECTORY>/SourceKit.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>)
endif()
