import SwiftUI

struct ProviderConfigurationList: View {
  @ObservedObject var settings: SettingsStore
  var compact = false

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
      ForEach(settings.visibleProviderIDs()) { providerID in
        ProviderConfigurationCard(settings: settings, providerID: providerID, compact: compact)
      }
    }
  }

  private var columns: [GridItem] {
    if compact {
      [GridItem(.adaptive(minimum: 260), spacing: 12)]
    } else {
      [GridItem(.adaptive(minimum: 320), spacing: 12)]
    }
  }
}

private struct ProviderConfigurationCard: View {
  @ObservedObject var settings: SettingsStore
  let providerID: ProviderID
  var compact: Bool

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        header

        TextField("Display Name", text: configurationBinding(\.displayName))
          .textFieldStyle(.roundedBorder)

        if providerID.isLLMProvider {
          TextField("Base URL", text: configurationBinding(\.baseURL))
            .textFieldStyle(.roundedBorder)

          TextField("Model", text: configurationBinding(\.model))
            .textFieldStyle(.roundedBorder)

          SecureField("API key", text: apiKeyBinding)
            .textFieldStyle(.roundedBorder)
        } else {
          Text("Uses the macOS system dictionary.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    } label: {
      HStack(spacing: 8) {
        Label(configuration.effectiveDisplayName, systemImage: providerID.systemImage)

        if configuration.effectiveDisplayName != providerID.displayName {
          Text(providerID.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Toggle("Enabled", isOn: configurationBinding(\.isEnabled))
        .toggleStyle(.switch)

      Spacer()

      if providerID.needsAPIKey {
        Label(settings.hasAPIKey(for: providerID) ? "Key saved" : "No key", systemImage: settings.hasAPIKey(for: providerID) ? "key.fill" : "key")
          .font(.caption)
          .foregroundStyle(settings.hasAPIKey(for: providerID) ? .green : .secondary)
      }
    }
    .font(.caption)
  }

  private var configuration: ProviderConfiguration {
    settings.configuration(for: providerID)
  }

  private func configurationBinding<Value: Equatable>(_ keyPath: WritableKeyPath<ProviderConfiguration, Value>) -> Binding<Value> {
    Binding {
      settings.configuration(for: providerID)[keyPath: keyPath]
    } set: { value in
      var configuration = settings.configuration(for: providerID)
      guard configuration[keyPath: keyPath] != value else {
        return
      }
      configuration[keyPath: keyPath] = value
      settings.updateConfiguration(configuration)
    }
  }

  private var apiKeyBinding: Binding<String> {
    Binding {
      settings.apiKey(for: providerID)
    } set: { value in
      guard settings.apiKey(for: providerID) != value else {
        return
      }
      settings.setAPIKey(value, for: providerID)
    }
  }
}
