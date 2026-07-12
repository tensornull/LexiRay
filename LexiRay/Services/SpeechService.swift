import AVFoundation
import Foundation

struct SpeechUtteranceState {
  private(set) var activeID: ObjectIdentifier?

  mutating func start(_ id: ObjectIdentifier) {
    activeID = id
  }

  mutating func stop() {
    activeID = nil
  }

  mutating func complete(_ id: ObjectIdentifier) -> Bool {
    guard activeID == id else {
      return false
    }
    activeID = nil
    return true
  }
}

@MainActor
protocol SpeechControlling: AnyObject {
  var isSpeaking: Bool { get }
  var onStateChange: ((Bool) -> Void)? { get set }

  @discardableResult
  func speak(_ text: String, languageCode: String?) -> Bool
  func stop()
}

@MainActor
final class SpeechService: NSObject, SpeechControlling, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var utteranceState = SpeechUtteranceState()
  private(set) var isSpeaking = false {
    didSet {
      guard oldValue != isSpeaking else {
        return
      }
      onStateChange?(isSpeaking)
    }
  }

  var onStateChange: ((Bool) -> Void)?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  @discardableResult
  func speak(_ text: String, languageCode: String?) -> Bool {
    let value = text.trimmedForQuery
    guard !value.isEmpty else {
      return false
    }

    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: value)
    utterance.voice = Self.voice(for: languageCode)
    utteranceState.start(ObjectIdentifier(utterance))
    synthesizer.speak(utterance)
    isSpeaking = true
    return true
  }

  func stop() {
    guard synthesizer.isSpeaking || isSpeaking else {
      return
    }

    utteranceState.stop()
    synthesizer.stopSpeaking(at: .immediate)
    isSpeaking = false
  }

  nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      guard self?.utteranceState.complete(utteranceID) == true else {
        return
      }
      self?.isSpeaking = false
    }
  }

  nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      guard self?.utteranceState.complete(utteranceID) == true else {
        return
      }
      self?.isSpeaking = false
    }
  }

  static func voice(for languageCode: String?) -> AVSpeechSynthesisVoice? {
    guard let language = speechLanguageCode(for: languageCode) else {
      return nil
    }
    return AVSpeechSynthesisVoice(language: language)
  }

  static func speechLanguageCode(for languageCode: String?) -> String? {
    guard let languageCode = languageCode?.nonEmptyTrimmed else {
      return nil
    }

    if languageCode.hasPrefix("zh-Hans") {
      return "zh-CN"
    }

    if languageCode.hasPrefix("zh-Hant") {
      return "zh-TW"
    }

    switch languageCode {
    case "en":
      return "en-US"
    case "ja":
      return "ja-JP"
    case "ko":
      return "ko-KR"
    case "fr":
      return "fr-FR"
    case "de":
      return "de-DE"
    case "es":
      return "es-ES"
    case "it":
      return "it-IT"
    case "pt":
      return "pt-PT"
    default:
      return languageCode
    }
  }
}
