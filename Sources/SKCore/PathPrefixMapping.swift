import Foundation

public struct PathPrefixMapping {
  /// Path prefix to be replaced, typically the canonical or hermetic path.
  public let original: String

  /// Replacement path prefix, typically the path on the local machine.
  public let replacement: String

  public init(original: String, replacement: String) {
    self.original = original
    self.replacement = replacement
  }
}
