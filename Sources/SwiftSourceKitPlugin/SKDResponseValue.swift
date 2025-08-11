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

import Csourcekitd

/// Values that can be stored in a `SKDResponseDictionary` or `SKDResponseArray`.
///
/// - Warning: `SKDResponseDictionary.set` and `SKDResponseDictionaryArray.append`
///   switch exhaustively over this protocol.
///   Do not add new conformances without adding a new case in the `set` and `append` functions.
protocol SKDResponseValue {}

extension String: SKDResponseValue {}
extension Bool: SKDResponseValue {}
extension Int: SKDResponseValue {}
extension Int64: SKDResponseValue {}
extension Double: SKDResponseValue {}
extension sourcekitd_api_uid_t: SKDResponseValue {}
extension SKDResponseDictionaryBuilder: SKDResponseValue {}
extension SKDResponseArrayBuilder: SKDResponseValue {}
extension [SKDResponseValue]: SKDResponseValue {}
extension [sourcekitd_api_uid_t: SKDResponseValue]: SKDResponseValue {}
extension Optional: SKDResponseValue where Wrapped: SKDResponseValue {}
