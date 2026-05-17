import Carbon
import Foundation

@MainActor
final class GlobalHotKeyService {
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  func registerDefaultHotKey(action: @escaping @MainActor () -> Void) {
    unregister()

    Self.currentAction = action
    installEventHandlerIfNeeded()

    let hotKeyID = EventHotKeyID(
      signature: "LXR1".fourCharCodeValue,
      id: 1
    )

    let status = RegisterEventHotKey(
      UInt32(kVK_ANSI_D),
      UInt32(cmdKey) | UInt32(optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status == noErr {
      AppLog.hotKey.info("Registered global hotkey \(AppConstants.defaultHotKeyDescription, privacy: .public)")
    } else {
      AppLog.hotKey.error("Failed to register global hotkey: \(status)")
    }
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    hotKeyRef = nil
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    InstallEventHandler(
      GetApplicationEventTarget(),
      Self.hotKeyHandler,
      1,
      &eventType,
      nil,
      &eventHandler
    )
  }

  private nonisolated(unsafe) static var currentAction: (@MainActor () -> Void)?

  private nonisolated static let hotKeyHandler: EventHandlerUPP = { _, _, _ in
    Task { @MainActor in
      currentAction?()
    }
    return noErr
  }
}
