//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension CompletionItem {
  struct PriorityBucket: RawRepresentable, Comparable {
    var rawValue: Int

    init(rawValue: Int) {
      self.rawValue = rawValue
    }

    static let userPrioritized: PriorityBucket = .init(rawValue: 1)
    static let highlyLikely: PriorityBucket = .init(rawValue: 5)
    static let likely: PriorityBucket = .init(rawValue: 10)
    static let regular: PriorityBucket = .init(rawValue: 50)
    static let wordsInFile: PriorityBucket = .init(rawValue: 90)
    static let infrequentlyUsed: PriorityBucket = .init(rawValue: 100)
    static let unknown: PriorityBucket = .init(rawValue: .max)

    // Swift Semantic Entries
    static let unresolvedMember_EnumElement: PriorityBucket = .highlyLikely + -4
    static let unresolvedMember_Var: PriorityBucket = .highlyLikely + -3
    static let unresolvedMember_Func: PriorityBucket = .highlyLikely + -2
    static let unresolvedMember_Constructor: PriorityBucket = .highlyLikely + -1
    static let unresolvedMember_Other: PriorityBucket = .regular + 0
    static let constructor: PriorityBucket = .highlyLikely + 0
    static let invalidTypeMatch: PriorityBucket = .infrequentlyUsed + 0
    static let otherModule_TypeMatch: PriorityBucket = .likely + 0
    static let otherModule_TypeMismatch: PriorityBucket = .regular + 0
    static let thisModule_TypeMatch: PriorityBucket = .likely + -1
    static let thisModule_TypeMismatch: PriorityBucket = .regular + -1
    static let noContext_TypeMatch: PriorityBucket = .likely + 0
    static let noContext_TypeMismatch: PriorityBucket = .regular + 0
    static let superClass_TypeMatch: PriorityBucket = .likely + -3
    static let superClass_TypeMismatch: PriorityBucket = .likely + 0
    static let thisClass_TypeMatch: PriorityBucket = .likely + -4
    static let thisClass_TypeMismatch: PriorityBucket = .likely + -1
    static let local_TypeMatch: PriorityBucket = .highlyLikely + 0
    static let local_TypeMismatch: PriorityBucket = .likely + -2
    static let otherClass_TypeMatch: PriorityBucket = .highlyLikely + 0
    static let otherClass_TypeMismatch: PriorityBucket = .likely + 0
    static let exprSpecific: PriorityBucket = .highlyLikely + 0

    var scoreCoefficient: Double {
      let clipped = max(min(self.rawValue, 100), 0)
      let v = Double(100 - clipped) / 100.0
      return 1.0 + v * v * v
    }

    static func + (lhs: PriorityBucket, rhs: Int) -> PriorityBucket {
      return PriorityBucket(rawValue: lhs.rawValue + rhs)
    }
    static func - (lhs: PriorityBucket, rhs: Int) -> PriorityBucket {
      return PriorityBucket(rawValue: lhs.rawValue - rhs)
    }
    static func < (lhs: PriorityBucket, rhs: PriorityBucket) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }
  }
}
