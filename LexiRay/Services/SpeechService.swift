import AVFoundation
import Foundation

@MainActor
final class SpeechService {
  private let synthesizer = AVSpeechSynthesizer()

  func speak(_ text: String) {
    let value = text.trimmedForQuery
    guard !value.isEmpty else {
      return
    }

    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: value)
    synthesizer.speak(utterance)
  }
}
