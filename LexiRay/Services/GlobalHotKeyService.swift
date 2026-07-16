import Carbon
import Foundation

enum HotKeyRegistrationStatus: Equatable {
  case registered
  case conflict
  case invalid
  case systemError(OSStatus)

  var detail: String {
    switch self {
    case .registered:
      "Registered"
    case .conflict:
      "Shortcut is already in use."
    case .invalid:
      "Shortcut is invalid."
    case .systemError:
      "Registration failed."
    }
  }

  var isFailure: Bool {
    self != .registered
  }
}

struct HotKeyRegistrationResults: Equatable {
  let translate: HotKeyRegistrationStatus
  let ocr: HotKeyRegistrationStatus

  static let registered = HotKeyRegistrationResults(translate: .registered, ocr: .registered)
}

@MainActor
protocol HotKeyRegistering: AnyObject {
  func registerDefaultHotKeys(
    translateHotKey: HotKeyConfiguration,
    ocrHotKey: HotKeyConfiguration,
    translate: @escaping @MainActor () -> Void,
    ocr: @escaping @MainActor () -> Void
  ) -> HotKeyRegistrationResults
  func unregister()
}

@MainActor
final class GlobalHotKeyService: HotKeyRegistering {
  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var eventHandler: EventHandlerRef?

  nonisolated static func registrationStatus(isValid: Bool, osStatus: OSStatus) -> HotKeyRegistrationStatus {
    guard isValid else {
      return .invalid
    }
    if osStatus == noErr {
      return .registered
    }
    if osStatus == eventHotKeyExistsErr {
      return .conflict
    }
    return .systemError(osStatus)
  }

  static func independentlyRegister(
    translateHotKey: HotKeyConfiguration,
    ocrHotKey: HotKeyConfiguration,
    register: (HotKeyConfiguration, UInt32) -> HotKeyRegistrationStatus
  ) -> HotKeyRegistrationResults {
    let translateStatus = register(translateHotKey, HotKeyID.translate.rawValue)
    let ocrStatus = register(ocrHotKey, HotKeyID.ocr.rawValue)
    return HotKeyRegistrationResults(translate: translateStatus, ocr: ocrStatus)
  }

  func registerDefaultHotKeys(
    translateHotKey: HotKeyConfiguration,
    ocrHotKey: HotKeyConfiguration,
    translate: @escaping @MainActor () -> Void,
    ocr: @escaping @MainActor () -> Void
  ) -> HotKeyRegistrationResults {
    unregister()

    Self.currentActions = [
      HotKeyID.translate.rawValue: translate,
      HotKeyID.ocr.rawValue: ocr
    ]
    let handlerStatus = installEventHandlerIfNeeded()
    guard handlerStatus == noErr else {
      let failure = HotKeyRegistrationStatus.systemError(handlerStatus)
      return HotKeyRegistrationResults(translate: failure, ocr: failure)
    }
    return Self.independentlyRegister(
      translateHotKey: translateHotKey,
      ocrHotKey: ocrHotKey
    ) { [weak self] hotKey, rawID in
      guard let self, let id = HotKeyID(rawValue: rawID) else {
        return .invalid
      }
      return register(hotKey: hotKey, id: id)
    }
  }

  func unregister() {
    for hotKeyRef in hotKeyRefs.values {
      UnregisterEventHotKey(hotKeyRef)
    }
    hotKeyRefs.removeAll()
  }

  private func register(hotKey: HotKeyConfiguration, id: HotKeyID) -> HotKeyRegistrationStatus {
    guard hotKey.isValidGlobalShortcut else {
      AppLog.hotKey.error("Skipped invalid global hotkey \(hotKey.displayString, privacy: .public)")
      return .invalid
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
      return .registered
    } else {
      AppLog.hotKey.error("Failed to register global hotkey: \(status)")
      return Self.registrationStatus(isValid: true, osStatus: status)
    }
  }

  private func installEventHandlerIfNeeded() -> OSStatus {
    guard eventHandler == nil else {
      return noErr
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    return InstallEventHandler(
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
