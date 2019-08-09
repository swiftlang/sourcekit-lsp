import LanguageServerProtocol

public struct RefereshDocumentsNotification: NotificationType {
  public static let method: String = "build/refreshDocuments"

  /// The changed documents.
  public var uris: [URL]

  public init(uris: [URL]) {
    self.uris = uris
  }
}
