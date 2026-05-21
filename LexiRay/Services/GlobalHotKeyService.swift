import Carbon
import Foundation

@MainActor
protocol HotKeyRegistering: AnyObject {
  func registerDefaultHotKeys(
    translateHotKey: HotKeyConfiguration,
    ocrHotKey: HotKeyConfiguration,
    translate: @escaping @MainActor () -> Void,
    ocr: @escaping @MainActor () -> Void
  )
  func unregister()
}

@MainActor
final class GlobalHotKeyService: HotKeyRegistering {
  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var eventHandler: EventHandlerRef?

  func registerDefaultHotKeys(
    translateHotKey: HotKeyConfiguration,
    ocrHotKey: HotKeyConfiguration,
    translate: @escaping @MainActor () -> Void,
    ocr: @escaping @MainActor () -> Void
  ) {
    unregister()

    Self.currentActions = [
      HotKeyID.translate.rawValue: translate,
      HotKeyID.ocr.rawValue: ocr
    ]
    installEventHandlerIfNeeded()
    register(hotKey: translateHotKey, id: .translate)
    register(hotKey: ocrHotKey, id: .ocr)
  }

  func unregister() {
    for hotKeyRef in hotKeyRefs.values {
      UnregisterEventHotKey(hotKeyRef)
    }
    hotKeyRefs.removeAll()
  }

  private func register(hotKey: HotKeyConfiguration, id: HotKeyID) {
    guard hotKey.isValidGlobalShortcut else {
      AppLog.hotKey.error("Skipped invalid global hotkey \(hotKey.displayString, privacy: .public)")
      return
    }

    let hotKeyID = EventHotKeyID(
      signature: "LXR1".fourCharCodeValue,
      id: id.rawValue
    )

    var hotKeyRef: EventHotKeyRef?
    let status = RegisterEventHotKey(
      hotKey.keyCode,
      hotKey.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status == noErr, let hotKeyRef {
      hotKeyRefs[id.rawValue] = hotKeyRef
      AppLog.hotKey.info("Registered global hotkey \(hotKey.displayString, privacy: .public)")
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
