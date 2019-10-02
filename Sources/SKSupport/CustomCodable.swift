//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Property wrapper allowing per-property customization of how the value is
/// encoded/decoded when using Codable.
///
/// CustomCodable is generic over a `CustomCoder: CustomCodableWrapper`, which
/// wraps the underlying value, and provides the specific Codable implementation.
/// Since each instance of CustomCodable provides its own CustomCoder wrapper,
/// properties of the same type can provide different Codable implementations
/// within the same container.
///
/// Example: change the encoding of a property `foo` in the following struct to
/// do its encoding through a String instead of the normal Codable implementation.
///
/// ```
/// struct MyStruct: Codable {
///   @CustomCodable<SillyIntCoding> var foo: Int
/// }
///
/// struct SillyIntCoding: CustomCodableWrapper {
///   init(from decoder: Decoder) throws {
///     wrappedValue = try Int(decoder.singleValueContainer().decoder(String.self))!
///   }
///   func encode(to encoder: Encoder) throws {
///     try encoder.singleValueContainer().encode("\(wrappedValue)")
///   }
///   var wrappedValue: Int { get }
///   init(wrappedValue: WrappedValue) { self.wrappedValue = wrappedValue }
/// }
/// ```
///
/// * Note: Unfortunately this wrapper does not work perfectly with `Optional`.
///   While you can add a conformance for it, it will `encodeNil` rather than
///   using `encodeIfPresent` on the containing type, since the synthesized
///   implementation only uses `encodeIfPresent` if the property itself is
///   `Optional`.
@propertyWrapper
public struct CustomCodable<CustomCoder: CustomCodableWrapper> {

  /// The underlying value.
  public var wrappedValue: CustomCoder.WrappedValue

  public init(wrappedValue: CustomCoder.WrappedValue) {
    self.wrappedValue = wrappedValue
  }
}

extension CustomCodable: Codable {
  public init(from decoder: Decoder) throws {
    self.wrappedValue = try CustomCoder(from: decoder).wrappedValue
  }

  public func encode(to encoder: Encoder) throws {
    try CustomCoder(wrappedValue: self.wrappedValue).encode(to: encoder)
  }
}

extension CustomCodable: Equatable where CustomCoder.WrappedValue: Equatable {}
extension CustomCodable: Hashable where CustomCoder.WrappedValue: Hashable {}

/// Wrapper type providing a Codable implementation for use with `CustomCodable`.
public protocol CustomCodableWrapper: Codable {

  /// The type of the underlying value being wrapped.
  associatedtype WrappedValue

  /// The underlying value.
  var wrappedValue: WrappedValue { get }

  /// Create a wrapper from an underlying value.
  init(wrappedValue: WrappedValue)
}
