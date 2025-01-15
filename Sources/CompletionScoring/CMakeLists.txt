set(sources 
  Semantics/SemanticClassification.swift
  Semantics/CompletionScore.swift
  Semantics/Components
  Semantics/Components/TypeCompatibility.swift
  Semantics/Components/StructuralProximity.swift
  Semantics/Components/Flair.swift
  Semantics/Components/CompletionKind.swift
  Semantics/Components/Popularity.swift
  Semantics/Components/ScopeProximity.swift
  Semantics/Components/Availability.swift
  Semantics/Components/SynchronicityCompatibility.swift
  Semantics/Components/PopularityIndex.swift
  Semantics/Components/ModuleProximity.swift
  Semantics/Components/PopularityTable.swift
  Utilities/UnsafeStackAllocator.swift
  Utilities/Serialization
  Utilities/Serialization/BinaryCodable.swift
  Utilities/Serialization/BinaryEncoder.swift
  Utilities/Serialization/BinaryDecoder.swift
  Utilities/Serialization/Conformances
  Utilities/Serialization/Conformances/Dictionary+BinaryCodable.swift
  Utilities/Serialization/Conformances/OptionSet+BinaryCodable.swift
  Utilities/Serialization/Conformances/Optional+BinaryCodable.swift
  Utilities/Serialization/Conformances/Scalars+BinaryCodable.swift
  Utilities/Serialization/Conformances/String+BinaryCodable.swift
  Utilities/Serialization/Conformances/Array+BinaryCodable.swift
  Utilities/SwiftExtensions.swift
  Utilities/SelectTopK.swift
  Utilities/UnsafeArray.swift
  Text/CandidateBatch.swift
  Text/MatchCollator.Match.swift
  Text/UTF8Byte.swift
  Text/MatchCollator.swift
  Text/InfluencingIdentifiers.swift
  Text/MatchCollator.Selection.swift
  Text/ScoredMatchSelector.swift
  Text/RejectionFilter.swift
  Text/Pattern.swift)

add_library(CompletionScoring STATIC ${sources})
set_target_properties(CompletionScoring PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(CompletionScoring PUBLIC
  CCompletionScoring)

add_library(CompletionScoringForPlugin STATIC ${sources})
set_target_properties(CompletionScoringForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(CompletionScoringForPlugin PUBLIC
  CCompletionScoring)
