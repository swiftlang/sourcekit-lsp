add_library(Diagnose STATIC
  CommandLineArgumentsReducer.swift
  DebugCommand.swift
  DiagnoseCommand.swift
  GenericError.swift
  IndexCommand.swift
  MergeSwiftFiles.swift
  OSLogScraper.swift
  ReduceCommand.swift
  ReduceFrontendCommand.swift
  ReduceSourceKitDRequest.swift
  ReduceSwiftFrontend.swift
  ReproducerBundle.swift
  RequestInfo.swift
  RunSourcekitdRequestCommand.swift
  SourceKitD+RunWithYaml.swift
  SourceKitDRequestExecutor.swift
  SourceReducer.swift
  StderrStreamConcurrencySafe.swift
  SwiftFrontendCrashScraper.swift
  Toolchain+SwiftFrontend.swift
  Toolchain+PluginPaths.swift
  TraceFromSignpostsCommand.swift)

set_target_properties(Diagnose PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(Diagnose PUBLIC
  BuildServerIntegration
  Csourcekitd
  InProcessClient
  LanguageServerProtocolExtensions
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SwiftToolsProtocols::SKLogging
  SKOptions
  SourceKitD
  SourceKitLSP
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  ToolchainRegistry
  ArgumentParser
  SwiftSyntax::SwiftIDEUtils
  SwiftSyntax::SwiftSyntax
  SwiftSyntax::SwiftParser
  TSCBasic
  TSCLibc
  TSCUtility
)

target_link_libraries(Diagnose PRIVATE
  SKUtilities
  TSCExtensions
)
