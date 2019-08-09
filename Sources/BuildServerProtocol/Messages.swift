import LanguageServerProtocol

fileprivate let requestTypes = [
  FlagRequest.self,
]

fileprivate let notificationTypes = [
  RefereshDocumentsNotification.self,
]

public let bspRegistry = MessageRegistry(requests: requestTypes, notifications: notificationTypes)
