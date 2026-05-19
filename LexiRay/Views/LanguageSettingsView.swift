import SwiftUI

struct LanguageSettingsView: View {
  @ObservedObject var settings: SettingsStore
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 12) {
      HStack(spacing: 12) {
        TextField("Language 1", text: language1)
          .textFieldStyle(.roundedBorder)

        Image(systemName: settings.autoSwitchLanguages ? "arrow.left.arrow.right" : "arrow.right")
          .foregroundStyle(.secondary)
          .frame(width: 22)

        TextField("Language 2", text: language2)
          .textFieldStyle(.roundedBorder)
      }

      Toggle("Auto switch", isOn: autoSwitchLanguages)
    }
  }

  private var language1: Binding<String> {
    Binding(
      get: { settings.language1 },
      set: { newValue in
        guard settings.language1 != newValue else {
          return
        }
        settings.language1 = newValue
      }
    )
  }

  private var language2: Binding<String> {
    Binding(
      get: { settings.language2 },
      set: { newValue in
        guard settings.language2 != newValue else {
          return
        }
        settings.language2 = newValue
      }
    )
  }

  private var autoSwitchLanguages: Binding<Bool> {
    Binding(
      get: { settings.autoSwitchLanguages },
      set: { newValue in
        guard settings.autoSwitchLanguages != newValue else {
          return
        }
        settings.autoSwitchLanguages = newValue
      }
    )
  }
}
