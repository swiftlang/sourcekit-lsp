set(sources
  AttributeSyntax+isNamed.swift
  FunctionDeclSyntax+IsXCTestFunction.swift
  MemberAccessExprSyntax+FullyQualifiedName.swift
  SwiftTestingDisabledTrait.swift
)

add_library(SwiftSyntaxExtensions STATIC ${sources})

set_target_properties(SwiftSyntaxExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(SwiftSyntaxExtensions PUBLIC
  SwiftSyntax::SwiftSyntax
)
