
add_executable(sourcekit-lsp
  SourceKitLSP.swift)
target_link_libraries(sourcekit-lsp PRIVATE
  BuildSystemIntegration
  Diagnose
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SemanticIndex
  SKOptions
  SKSupport
  SourceKitLSP
  ToolchainRegistry
  ArgumentParser
  TSCBasic)
target_compile_options(sourcekit-lsp PRIVATE
  -parse-as-library)
target_link_libraries(sourcekit-lsp PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

install(TARGETS sourcekit-lsp
  DESTINATION bin)
