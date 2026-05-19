import SwiftUI

struct ProviderConfigurationList: View {
  @ObservedObject var settings: SettingsStore
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Spacer()
        Menu {
          ForEach(ProviderID.addableCases) { providerID in
            Button {
              settings.addProvider(providerID: providerID)
            } label: {
              Label(providerID.displayName, systemImage: providerID.systemImage)
            }
          }
        } label: {
          Label("Add Provider", systemImage: "plus")
        }
        .menuStyle(.borderedButton)
      }

      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        ForEach(settings.visibleProviderConfigurations()) { configuration in
          ProviderConfigurationCard(settings: settings, configurationID: configuration.id, compact: compact)
        }
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
  let configurationID: String
  var compact: Bool

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        header

        TextField("Display Name", text: configurationBinding(\.displayName))
          .textFieldStyle(.roundedBorder)

        if configuration.providerID.isLLMProvider {
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
        Label(configuration.effectiveDisplayName, systemImage: configuration.providerID.systemImage)

        if configuration.effectiveDisplayName != configuration.providerID.displayName {
          Text(configuration.providerID.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button(role: .destructive) {
          settings.removeProvider(configurationID: configurationID)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("Remove Provider")
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Toggle("Enabled", isOn: configurationBinding(\.isEnabled))
        .toggleStyle(.switch)

      Spacer()

      if configuration.providerID.needsAPIKey {
        Label(settings.hasAPIKey(forConfigurationID: configurationID) ? "Key saved" : "No key", systemImage: settings.hasAPIKey(forConfigurationID: configurationID) ? "key.fill" : "key")
          .font(.caption)
          .foregroundStyle(settings.hasAPIKey(forConfigurationID: configurationID) ? .green : .secondary)
      }
    }
    .font(.caption)
  }

  private var configuration: ProviderConfiguration {
    settings.configuration(for: configurationID) ?? ProviderConfiguration.defaults(for: .openAIResponses)
  }

  private func configurationBinding<Value: Equatable>(_ keyPath: WritableKeyPath<ProviderConfiguration, Value>) -> Binding<Value> {
    Binding {
      configuration[keyPath: keyPath]
    } set: { value in
      guard var configuration = settings.configuration(for: configurationID) else {
        return
      }
      guard configuration[keyPath: keyPath] != value else {
        return
      }
      configuration[keyPath: keyPath] = value
      settings.updateConfiguration(configuration)
    }
  }

  private var apiKeyBinding: Binding<String> {
    Binding {
      settings.apiKey(forConfigurationID: configurationID)
    } set: { value in
      guard settings.apiKey(forConfigurationID: configurationID) != value else {
        return
      }
      settings.setAPIKey(value, forConfigurationID: configurationID)
    }
  }
}
