import LanguageServerProtocol

fileprivate let requestTypes: [_RequestType.Type] = [
  InitializeBuild.self,
  ShutdownBuild.self,
]

fileprivate let notificationTypes: [NotificationType.Type] = [
  InitializedBuildNotification.self,
  ExitBuildNotification.self,
]

public let bspRegistry = MessageRegistry(requests: requestTypes, notifications: notificationTypes)
