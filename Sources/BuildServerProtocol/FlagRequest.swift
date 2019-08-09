import LanguageServerProtocol

public struct FlagRequest: RequestType, Hashable {
  public static let method: String = "build/compilerFlags"
  public typealias Response = FlagResponse

  /// The document for the required flags.
  public var uri: URL

  public init(uri: URL) {
    self.uri = uri
  }
}
