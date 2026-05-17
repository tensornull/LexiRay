import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: SettingsStore

  var body: some View {
    Form {
      Section("Translation") {
        Picker("Provider", selection: $settings.preferredProvider) {
          ForEach(ProviderID.allCases) { provider in
            Text(provider.displayName)
              .tag(provider)
          }
        }

        TextField("Target language", text: $settings.targetLanguage)
        Toggle("Show provider details", isOn: $settings.showProviderDetails)
      }

      Section("OpenAI Compatible") {
        TextField("Base URL", text: $settings.openAIBaseURL)
        TextField("Model", text: $settings.openAIModel)
        SecureField("API key", text: $settings.openAIAPIKey)
      }

      Section("Permissions") {
        HStack {
          Label("Accessibility", systemImage: PermissionService.isAccessibilityTrusted ? "checkmark.circle.fill" : "lock.shield")
          Spacer()
          Button("Open Settings") {
            PermissionService.openAccessibilitySettings()
          }
        }

        HStack {
          Label("Automation", systemImage: "applescript")
          Spacer()
          Button("Open Settings") {
            PermissionService.openAutomationSettings()
          }
        }
      }

      Button("Reset Provider Settings") {
        settings.resetProviderSettings()
      }
    }
    .formStyle(.grouped)
    .padding(20)
  }
}
