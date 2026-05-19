import Carbon
import Foundation

@MainActor
final class GlobalHotKeyService {
  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var eventHandler: EventHandlerRef?

  func registerDefaultHotKeys(
    translate: @escaping @MainActor () -> Void,
    ocr: @escaping @MainActor () -> Void
  ) {
    unregister()

    Self.currentActions = [
      HotKeyID.translate.rawValue: translate,
      HotKeyID.ocr.rawValue: ocr
    ]
    installEventHandlerIfNeeded()
    register(keyCode: UInt32(kVK_ANSI_D), id: .translate, description: AppConstants.defaultHotKeyDescription)
    register(keyCode: UInt32(kVK_ANSI_O), id: .ocr, description: AppConstants.defaultOCRHotKeyDescription)
  }

  func unregister() {
    for hotKeyRef in hotKeyRefs.values {
      UnregisterEventHotKey(hotKeyRef)
    }
    hotKeyRefs.removeAll()
  }

  private func register(keyCode: UInt32, id: HotKeyID, description: String) {
    let hotKeyID = EventHotKeyID(
      signature: "LXR1".fourCharCodeValue,
      id: id.rawValue
    )

    var hotKeyRef: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      UInt32(cmdKey) | UInt32(optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status == noErr, let hotKeyRef {
      hotKeyRefs[id.rawValue] = hotKeyRef
      AppLog.hotKey.info("Registered global hotkey \(description, privacy: .public)")
    } else {
      AppLog.hotKey.error("Failed to register global hotkey: \(status)")
    }
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

  private nonisolated(unsafe) static var currentActions: [UInt32: @MainActor () -> Void] = [:]

  private nonisolated static let hotKeyHandler: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )

    guard status == noErr else {
      return status
    }

    Task { @MainActor in
      currentActions[hotKeyID.id]?()
    }
    return noErr
  }

  private enum HotKeyID: UInt32 {
    case translate = 1
    case ocr = 2
  }
}
