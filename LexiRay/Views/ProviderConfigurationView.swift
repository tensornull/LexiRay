import CoreTransferable
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let providerReorderType = UTType(exportedAs: "io.github.tensornull.lexiray.provider-order", conformingTo: .data)

private struct ProviderReorderPayload: Codable, Transferable {
  let configurationID: String

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: providerReorderType)
  }
}

struct ProviderConfigurationList: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var settings: SettingsStore
  var compact = false
  @State private var isEditing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Text(isEditing ? "Drag providers to change their order." : "Provider order is also used for translation results.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        Button(isEditing ? "Done" : "Edit Providers", systemImage: isEditing ? "checkmark" : "slider.horizontal.3") {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isEditing.toggle()
          }
        }
        .accessibilityIdentifier("ProviderEditButton")
        .disabled(settings.visibleProviderConfigurations().isEmpty && !isEditing)
      }

      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        ForEach(Array(settings.visibleProviderConfigurations().enumerated()), id: \.element.id) { index, configuration in
          if isEditing {
            ProviderReorderTile(
              settings: settings,
              configuration: configuration,
              index: index
            )
            .draggable(ProviderReorderPayload(configurationID: configuration.id))
            .dropDestination(for: ProviderReorderPayload.self) { payloads, _ in
              guard let sourceID = payloads.first?.configurationID,
                    sourceID != configuration.id,
                    settings.configuration(for: sourceID) != nil,
                    let destination = settings.visibleProviderConfigurations().firstIndex(where: { $0.id == configuration.id })
              else {
                AppLog.settings.debug("Provider reorder drop rejected")
                return false
              }
              AppLog.settings.debug("Provider reorder drop: \(sourceID, privacy: .public) to \(configuration.id, privacy: .public)")
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                settings.moveProvider(configurationID: sourceID, toVisibleIndex: destination)
              }
              return true
            }
          } else {
            ProviderConfigurationCard(settings: settings, configurationID: configuration.id, compact: compact)
          }
        }
      }
      .accessibilityIdentifier("ProviderConfigurationGrid")
    }
  }

  private var columns: [GridItem] {
    if compact {
      [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)]
    } else {
      [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)]
    }
  }
}

private struct ProviderReorderTile: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var settings: SettingsStore
  let configuration: ProviderConfiguration
  let index: Int
  @State private var wiggles = false

  var body: some View {
    HStack(spacing: 10) {
      Button(role: .destructive) {
        settings.removeProvider(configurationID: configuration.id)
      } label: {
        Image(systemName: "minus.circle.fill")
          .font(.title3)
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .red)
      }
      .buttonStyle(.borderless)
      .help("Remove \(configuration.effectiveDisplayName)")
      .accessibilityLabel("Remove \(configuration.effectiveDisplayName)")
      .accessibilityIdentifier("ProviderRemove-\(configuration.id)")

      ProviderIconView(providerID: configuration.providerID)
        .frame(width: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(configuration.effectiveDisplayName)
          .font(.headline)
          .lineLimit(2)
        Text("\(index + 1) · \(configuration.isEnabled ? "Enabled" : "Off")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 4)

      VStack(spacing: 5) {
        Button("Move Earlier", systemImage: "chevron.up") { move(by: -1) }
          .disabled(index == 0)
          .accessibilityIdentifier("ProviderMoveEarlier-\(configuration.id)")
        Button("Move Later", systemImage: "chevron.down") { move(by: 1) }
          .disabled(index == settings.visibleProviderConfigurations().count - 1)
          .accessibilityIdentifier("ProviderMoveLater-\(configuration.id)")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)

      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
        .accessibilityIdentifier("ProviderDragHandle-\(configuration.id)")
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .rotationEffect(.degrees(reduceMotion ? 0 : (wiggles ? 0.55 : -0.55)))
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16).repeatForever(autoreverses: true), value: wiggles)
    .onAppear { wiggles = !reduceMotion }
    .onChange(of: reduceMotion) { _, isReduced in
      wiggles = !isReduced
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(configuration.effectiveDisplayName)
    .accessibilityIdentifier("ProviderReorderTile-\(configuration.id)")
  }

  private func move(by offset: Int) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
      settings.moveProvider(configurationID: configuration.id, toVisibleIndex: index + offset)
    }
  }
}

private struct ProviderConfigurationCard: View {
  @ObservedObject var settings: SettingsStore
  let configurationID: String
  var compact: Bool
  @State private var showsAdvancedParameters = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      titleRow
      header

      TextField("Display Name", text: configurationBinding(\.displayName))
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("ProviderDisplayName-\(configurationID)")

      if configuration.providerID.isLLMProvider {
        TextField("Base URL", text: configurationBinding(\.baseURL))
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("ProviderBaseURL-\(configurationID)")

        TextField("Model", text: configurationBinding(\.model))
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("ProviderModel-\(configurationID)")

        SecureField("API key", text: apiKeyBinding)
          .textFieldStyle(.roundedBorder)

        if configuration.providerID == .openAIResponses {
          responsesAdvancedSection
        }
      } else {
        Text("Uses the macOS system dictionary.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(nsColor: .separatorColor).opacity(0.48), lineWidth: 1)
    }
  }

  private var titleRow: some View {
    HStack(spacing: 8) {
      ProviderIconView(providerID: configuration.providerID)
        .frame(width: 18)

      Text(configuration.effectiveDisplayName)
        .font(.headline)
        .lineLimit(1)

      if configuration.hasCustomDisplayName {
        Text(configuration.providerID.displayName)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
      }

      Spacer()
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

  private var responsesAdvancedSection: some View {
    DisclosureGroup("Advanced", isExpanded: $showsAdvancedParameters) {
      VStack(alignment: .leading, spacing: 9) {
        Text("Disabled parameters are omitted from OpenAI Responses requests.")
          .foregroundStyle(.secondary)

        optionalDoubleControl(
          title: "Temperature",
          keyPath: \.temperature,
          defaultValue: 0.2,
          range: 0 ... 2,
          step: 0.1
        )

        optionalIntControl(
          title: "Max output tokens",
          keyPath: \.maxOutputTokens,
          defaultValue: 2048,
          range: 1 ... 128_000,
          step: 256
        )

        optionalPicker(
          title: "Reasoning effort",
          keyPath: \.reasoningEffort,
          defaultValue: OpenAIReasoningEffort.low,
          options: OpenAIReasoningEffort.allCases
        )

        optionalPicker(
          title: "Reasoning summary",
          keyPath: \.reasoningSummary,
          defaultValue: OpenAIReasoningSummary.auto,
          options: OpenAIReasoningSummary.allCases
        )

        optionalPicker(
          title: "Text verbosity",
          keyPath: \.textVerbosity,
          defaultValue: OpenAITextVerbosity.medium,
          options: OpenAITextVerbosity.allCases
        )
      }
      .padding(.top, 8)
    }
    .font(.caption)
  }

  private func optionalDoubleControl(
    title: String,
    keyPath: WritableKeyPath<ProviderAdvancedParameters, Double?>,
    defaultValue: Double,
    range: ClosedRange<Double>,
    step: Double
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Toggle(title, isOn: optionalEnabledBinding(keyPath, defaultValue: defaultValue))
      Stepper(
        value: optionalValueBinding(keyPath, defaultValue: defaultValue),
        in: range,
        step: step
      ) {
        Text(String(format: "%.1f", configuration.advancedParameters[keyPath: keyPath] ?? defaultValue))
          .monospacedDigit()
      }
      .disabled(configuration.advancedParameters[keyPath: keyPath] == nil)
    }
  }

  private func optionalIntControl(
    title: String,
    keyPath: WritableKeyPath<ProviderAdvancedParameters, Int?>,
    defaultValue: Int,
    range: ClosedRange<Int>,
    step: Int
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Toggle(title, isOn: optionalEnabledBinding(keyPath, defaultValue: defaultValue))
      Stepper(
        value: optionalValueBinding(keyPath, defaultValue: defaultValue),
        in: range,
        step: step
      ) {
        Text("\(configuration.advancedParameters[keyPath: keyPath] ?? defaultValue)")
          .monospacedDigit()
      }
      .disabled(configuration.advancedParameters[keyPath: keyPath] == nil)
    }
  }

  private func optionalPicker<Value: ProviderAdvancedParameterOption>(
    title: String,
    keyPath: WritableKeyPath<ProviderAdvancedParameters, Value?>,
    defaultValue: Value,
    options: [Value]
  ) -> some View {
    HStack(spacing: 8) {
      Toggle(title, isOn: optionalEnabledBinding(keyPath, defaultValue: defaultValue))
      Spacer()
      Picker(title, selection: optionalValueBinding(keyPath, defaultValue: defaultValue)) {
        ForEach(options) { option in
          Text(option.displayName)
            .tag(option)
        }
      }
      .labelsHidden()
      .frame(width: 120)
      .disabled(configuration.advancedParameters[keyPath: keyPath] == nil)
    }
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

  private func optionalEnabledBinding<Value: Equatable>(
    _ keyPath: WritableKeyPath<ProviderAdvancedParameters, Value?>,
    defaultValue: Value
  ) -> Binding<Bool> {
    Binding {
      configuration.advancedParameters[keyPath: keyPath] != nil
    } set: { isEnabled in
      guard var configuration = settings.configuration(for: configurationID) else {
        return
      }
      let currentValue = configuration.advancedParameters[keyPath: keyPath]
      configuration.advancedParameters[keyPath: keyPath] = isEnabled ? (currentValue ?? defaultValue) : nil
      settings.updateConfiguration(configuration)
    }
  }

  private func optionalValueBinding<Value: Equatable>(
    _ keyPath: WritableKeyPath<ProviderAdvancedParameters, Value?>,
    defaultValue: Value
  ) -> Binding<Value> {
    Binding {
      configuration.advancedParameters[keyPath: keyPath] ?? defaultValue
    } set: { value in
      guard var configuration = settings.configuration(for: configurationID) else {
        return
      }
      guard configuration.advancedParameters[keyPath: keyPath] != value else {
        return
      }
      configuration.advancedParameters[keyPath: keyPath] = value
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

private protocol ProviderAdvancedParameterOption: CaseIterable, Identifiable, Hashable {
  var displayName: String { get }
}

extension OpenAIReasoningEffort: ProviderAdvancedParameterOption {}
extension OpenAIReasoningSummary: ProviderAdvancedParameterOption {}
extension OpenAITextVerbosity: ProviderAdvancedParameterOption {}
