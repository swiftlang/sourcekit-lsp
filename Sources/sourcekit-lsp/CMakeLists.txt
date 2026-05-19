
add_executable(sourcekit-lsp
  SourceKitLSP.swift)
target_link_libraries(sourcekit-lsp PRIVATE
  BuildServerIntegration
  Diagnose
  InProcessClient
  SwiftToolsProtocols::LanguageServerProtocol
  LanguageServerProtocolExtensions
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SemanticIndex
  SKOptions
  SourceKitLSP
  ToolchainRegistry
  ArgumentParser
  TSCBasic)
target_compile_options(sourcekit-lsp PRIVATE
  -parse-as-library)
target_link_libraries(sourcekit-lsp PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

set_target_properties(sourcekit-lsp PROPERTIES
  INSTALL_RPATH "$<$<PLATFORM_ID:Darwin>:@executable_path/../lib;@executable_path/../lib/swift/macosx;@executable_path/../lib/swift/host;@executable_path/../lib/swift/pm/llbuild>")

install(TARGETS sourcekit-lsp
  DESTINATION bin)
