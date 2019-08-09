import LanguageServerProtocol

public struct FlagResponse: ResponseType, Hashable {

  public var flags: [String]

  public init(flags: [String]) {
    self.flags = flags
  }
}
