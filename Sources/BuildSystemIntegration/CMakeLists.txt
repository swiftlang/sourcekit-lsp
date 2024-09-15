
add_library(BuildSystemIntegration STATIC
  BuildServerBuildSystem.swift
  BuildSystemManager.swift
  BuildSystemManagerDelegate.swift
  BuildSystemMessageDependencyTracker.swift
  BuildTargetIdentifierExtensions.swift
  BuiltInBuildSystem.swift
  BuiltInBuildSystemAdapter.swift
  CompilationDatabase.swift
  CompilationDatabaseBuildSystem.swift
  FallbackBuildSettings.swift
  FileBuildSettings.swift
  Language+InferredFromFileExtension.swift
  MainFilesProvider.swift
  PathPrefixMapping.swift
  PrefixMessageWithTaskEmoji.swift
  QueueBasedMessageHandler.swift
  SplitShellCommand.swift
  SwiftPMBuildSystem.swift
  TestBuildSystem.swift)
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
