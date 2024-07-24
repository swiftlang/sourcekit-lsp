import Foundation

package struct PathPrefixMapping: Sendable {
  /// Path prefix to be replaced, typically the canonical or hermetic path.
  package let original: String

  /// Replacement path prefix, typically the path on the local machine.
  package let replacement: String

  package init(original: String, replacement: String) {
    self.original = original
    self.replacement = replacement
  }
}
