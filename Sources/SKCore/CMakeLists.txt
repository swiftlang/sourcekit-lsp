
add_library(SKCore STATIC
  BuildConfiguration.swift
  BuildServerBuildSystem.swift
  BuildSystem.swift
  BuildSystemDelegate.swift
  BuildSystemManager.swift
  CompilationDatabase.swift
  CompilationDatabaseBuildSystem.swift
  FallbackBuildSystem.swift
  FileBuildSettings.swift
  IndexTaskID.swift
  MainFilesProvider.swift
  PathPrefixMapping.swift
  SourceKitLSPOptions.swift
  SplitShellCommand.swift
  WorkspaceType.swift)
set_target_properties(SKCore PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKCore PUBLIC
  BuildServerProtocol
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKLogging
  SKSupport
  SourceKitD
  SwiftExtensions
  ToolchainRegistry
  PackageModel
  TSCBasic)
