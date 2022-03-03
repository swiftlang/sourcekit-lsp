
add_executable(sourcekit-lsp
  main.swift)
target_link_libraries(sourcekit-lsp PRIVATE
  ArgumentParser
  LanguageServerProtocolJSONRPC
  SKCore
  SourceKitLSP
  TSCUtility)
target_link_libraries(sourcekit-lsp PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

install(TARGETS sourcekit-lsp
  DESTINATION bin)
