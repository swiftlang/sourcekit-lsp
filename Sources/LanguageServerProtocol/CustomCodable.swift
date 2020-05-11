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
@propertyWrapper
public struct CustomCodable<CustomCoder: CustomCodableWrapper> {

  public typealias CustomCoder = CustomCoder

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

extension Optional: CustomCodableWrapper where Wrapped: CustomCodableWrapper {
  public var wrappedValue: Wrapped.WrappedValue? { self?.wrappedValue }
  public init(wrappedValue: Wrapped.WrappedValue?) {
    self = wrappedValue.flatMap { Wrapped.init(wrappedValue: $0) }
  }
}

// The following extensions allow us to encode `CustomCodable<Optional<T>>`
// using `encodeIfPresent` (and `decodeIfPresent`) in synthesized `Codable`
// conformances. Without these, we would encode `nil` using `encodeNil` instead
// of skipping the key.

extension KeyedDecodingContainer {
  public func decode<T: CustomCodableWrapper>(
    _ type: CustomCodable<Optional<T>>.Type,
    forKey key: Key
  ) throws -> CustomCodable<Optional<T>> {
    CustomCodable<Optional<T>>(wrappedValue: try decodeIfPresent(T.self, forKey: key)?.wrappedValue)
  }
}

extension KeyedEncodingContainer {
  public mutating func encode<T: CustomCodableWrapper>(
    _ value: CustomCodable<Optional<T>>,
    forKey key: Key
  ) throws {
    try encodeIfPresent(value.wrappedValue.map {
      type(of: value).CustomCoder(wrappedValue: $0) }, forKey: key)
  }
}
