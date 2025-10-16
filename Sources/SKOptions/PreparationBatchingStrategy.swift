//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Defines the batch size for target preparation.
///
/// If nil, SourceKit-LSP will default to preparing 1 target at a time.
///
/// - discriminator: strategy
public enum PreparationBatchingStrategy: Sendable, Equatable {
  /// Prepare a fixed number of targets in a single batch.
  ///
  /// `batchSize`: The number of targets to prepare in each batch.
  case target(batchSize: Int)
}

extension PreparationBatchingStrategy: Codable {
  private enum CodingKeys: String, CodingKey {
    case strategy
    case batchSize
  }
  
  private enum StrategyValue: String, Codable {
    case target
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let strategy = try container.decode(StrategyValue.self, forKey: .strategy)
    
    switch strategy {
    case .target:
      let batchSize = try container.decode(Int.self, forKey: .batchSize)
      self = .target(batchSize: batchSize)
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .target(let batchSize):
      try container.encode(StrategyValue.target, forKey: .strategy)
      try container.encode(batchSize, forKey: .batchSize)
    }
  }
}