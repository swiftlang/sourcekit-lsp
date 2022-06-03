import Foundation

public struct PathPrefixMapping {
  /// Path prefix to be replaced, typically the canonical or hermetic path.
  let original: String

  /// Replacement path prefix, typically the path on the local machine.
  let replacement: String

  public init(original: String, replacement: String) {
    self.original = original
    self.replacement = replacement
  }
}
