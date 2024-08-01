
add_library(BuildSystemIntegration STATIC
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
  SplitShellCommand.swift
  SwiftPMBuildSystem.swift)
set_target_properties(BuildSystemIntegration PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildSystemIntegration PUBLIC
  BuildServerProtocol
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKLogging
  SKOptions
  SKSupport
  SourceKitD
  SwiftExtensions
  ToolchainRegistry
  PackageModel
  TSCBasic
  Build
  SourceKitLSPAPI)
