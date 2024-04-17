
add_library(SKCore STATIC
  BuildServerBuildSystem.swift
  BuildSetup.swift
  BuildSystem.swift
  BuildSystemDelegate.swift
  BuildSystemManager.swift
  CompilationDatabase.swift
  CompilationDatabaseBuildSystem.swift
  Debouncer.swift
  FallbackBuildSystem.swift
  FileBuildSettings.swift
  MainFilesProvider.swift
  PathPrefixMapping.swift
  SplitShellCommand.swift
  Toolchain.swift
  ToolchainRegistry.swift
  XCToolchainPlist.swift)
set_target_properties(SKCore PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKCore PUBLIC
  BuildServerProtocol
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  LSPLogging
  SKSupport
  SourceKitD
  PackageModel
  TSCBasic)
