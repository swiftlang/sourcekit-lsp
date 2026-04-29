# Adding LSP and BSP Messages

This document lists every file that must be updated when adding a new LSP or BSP request or notification.

## LSP Message

### In `swift-tools-protocols`

- [ ] Add the Swift file under `Sources/LanguageServerProtocol/Requests/` *(request)* or `Sources/LanguageServerProtocol/Notifications/` *(notification)*
- [ ] `Sources/LanguageServerProtocol/CMakeLists.txt`:
  - [ ] Add the file in alphabetical order
- [ ] `Sources/LanguageServerProtocol/Messages.swift`:
  - [ ] Add to `builtinRequests` *(request)* or `builtinNotifications` *(notification)*

### In `sourcekit-lsp`

- [ ] `Sources/SourceKitLSP/MessageHandlingDependencyTracker.swift`:
  - [ ] *(client → server, request)* Add a case to `init(_ request:)`
  - [ ] *(client → server, notification)* Add a case to `init(_ notification:)`
- [ ] `Sources/SourceKitLSP/SourceKitLSPServer.swift`:
  - [ ] *(client → server, request)* Add a case to `handle(request:id:reply:)`
  - [ ] *(client → server, notification)* Add a case to `handle(notification:)`
  - [ ] Advertise via `serverCapabilities()`
  - [ ] If handled by a language service: also advertise in each `LanguageService.initialize` conforming method
  - [ ] If experimental *(server → client)*: check the client capability before sending
- [ ] `Sources/SourceKitLSP/CapabilityRegistry.swift`:
  - [ ] If gated on an experimental **client** capability, add a helper property
- [ ] `Contributor Documentation/LSP Extensions.md`:
  - [ ] Document if it is an LSP extension

## BSP Message

### In `swift-tools-protocols`

- [ ] Add the Swift file under `Sources/BuildServerProtocol/Messages/`
- [ ] `Sources/BuildServerProtocol/CMakeLists.txt`:
  - [ ] Add the file in alphabetical order
- [ ] `Sources/BuildServerProtocol/Messages.swift`:
  - [ ] Add to `requestTypes` *(request)* or `notificationTypes` *(notification)*

### In `sourcekit-lsp`

- [ ] `Sources/BuildServerIntegration/BuildServerMessageDependencyTracker.swift`:
  - [ ] *(build server → SourceKit-LSP, request)* Add a case to `init(_ request:)`
  - [ ] *(build server → SourceKit-LSP, notification)* Add a case to `init(_ notification:)`
- [ ] `Sources/BuildServerIntegration/BuiltInBuildServer.swift`:
  - [ ] *(SourceKit-LSP → build server, request)* Add the request handler method to the `BuiltInBuildServer` protocol
  - [ ] *(SourceKit-LSP → build server, notification)* Add the notification handler method to the `BuiltInBuildServer` protocol
- [ ] `Sources/BuildServerIntegration/BuiltInBuildServerAdapter.swift`:
  - [ ] *(SourceKit-LSP → build server, request)* Add a case to `handle(request:id:reply:)`
  - [ ] *(SourceKit-LSP → build server, notification)* Add a case to `handle(notification:)`
- [ ] `Sources/BuildServerIntegration/BuildServerManager.swift`:
  - [ ] *(build server → SourceKit-LSP, request)* Add a case to `handle(request:id:reply:)`
  - [ ] *(build server → SourceKit-LSP, notification)* Add a case to `handle(notification:)`
- [ ] `Contributor Documentation/BSP Extensions.md`:
  - [ ] Document if it is a BSP extension
