import SwiftUI

struct DashboardSettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var controller: LexiRayController
  @ObservedObject private var settings: SettingsStore
  @ObservedObject private var permissionMonitor: PermissionStatusMonitor
  @State private var loginItemStatus = LoginItemService.status

  init(controller: LexiRayController) {
    self.controller = controller
    settings = controller.settings
    permissionMonitor = controller.permissionMonitor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      appPanel
      translationPanel
      hotKeyPanel
      floatingPanel
      historyPanel
      appIdentityPanel
      permissionPanel
      advancedPanel
    }
    .onAppear(perform: refreshRuntimeState)
    .onReceive(permissionMonitor.refreshEvents) {
      refreshLoginItemStatus()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }
      refreshRuntimeState()
    }
  }

  private var appPanel: some View {
    SettingsSection(title: "App", systemName: "app.badge") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle("Show menu bar icon", isOn: showsMenuBarIcon)

        Toggle("Start at login", isOn: startAtLogin)
          .disabled(loginItemStatus.isUnavailable)

        if let detail = loginItemStatus.detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(loginItemDetailColor)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var translationPanel: some View {
    SettingsSection(title: "Translation", systemName: "translate") {
      VStack(alignment: .leading, spacing: 10) {
        Picker("Auto copy", selection: autoCopyMode) {
          ForEach(AutoCopyMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.menu)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var hotKeyPanel: some View {
    SettingsSection(title: "Hotkeys", systemName: "keyboard") {
      VStack(alignment: .leading, spacing: 12) {
        HotKeySettingsRow(
          title: "Translate selection",
          hotKey: translateHotKey,
          defaultHotKey: .defaultTranslate
        )

        HotKeySettingsRow(
          title: "OCR region",
          hotKey: ocrHotKey,
          defaultHotKey: .defaultOCR
        )

        Button("Restore Default Hotkeys") {
          settings.resetHotKeys()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var floatingPanel: some View {
    SettingsSection(title: "Floating Panel", systemName: "macwindow.on.rectangle") {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Default position", selection: floatingPanelPlacement) {
          ForEach(FloatingPanelPlacement.allCases) { placement in
            Text(placement.title).tag(placement)
          }
        }
        .pickerStyle(.menu)

        if let origin = settings.floatingPanelLastOrigin {
          LabeledContent("Last position", value: "\(Int(origin.x)), \(Int(origin.y))")
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var historyPanel: some View {
    SettingsSection(title: "History", systemName: "clock.arrow.circlepath") {
      VStack(alignment: .leading, spacing: 12) {
        Stepper(
          value: translationHistoryLimit,
          in: SettingsStore.translationHistoryLimitRange
        ) {
          LabeledContent("Maximum saved items", value: "\(settings.translationHistoryLimit)")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var permissionPanel: some View {
    SettingsSection(title: "Permissions", systemName: "lock.shield") {
      VStack(alignment: .leading, spacing: 10) {
        PermissionSettingsRow(
          title: "Accessibility",
          detail: permissionMonitor.status.isAccessibilityTrusted ? "Enabled" : "Needed for selected text",
          isEnabled: permissionMonitor.status.isAccessibilityTrusted,
          action: openAccessibilitySettings
        )

        PermissionSettingsRow(
          title: "Screen Recording",
          detail: permissionMonitor.status.isScreenCaptureTrusted ? "Enabled" : "Needed for OCR",
          isEnabled: permissionMonitor.status.isScreenCaptureTrusted,
          action: openScreenCaptureSettings
        )

        PermissionSettingsRow(
          title: "Automation",
          detail: "Requested when browser selection is used",
          isEnabled: nil,
          action: PermissionService.openAutomationSettings
        )
      }
    }
  }

  private var appIdentityPanel: some View {
    SettingsSection(title: "App Identity", systemName: appIdentityIconName) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: appIdentityIconName)
            .foregroundStyle(appIdentityColor)

          VStack(alignment: .leading, spacing: 3) {
            Text(controller.appIdentity.statusTitle)
              .font(.body.weight(.medium))
            Text(controller.appIdentity.signatureSummary)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }

        AppIdentityDetailRow(title: "Authority", value: controller.appIdentity.certificateAuthority ?? "None")
        AppIdentityDetailRow(title: "Path", value: controller.appIdentity.bundlePath)

        if !controller.appIdentity.duplicateExecutablePaths.isEmpty {
          Text("Other running copies: \(controller.appIdentity.duplicateExecutablePaths.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 10) {
          Button("Open Install Location") {
            controller.openInstallLocation()
          }
          .accessibilityIdentifier("AppIdentityOpenInstallLocationButton")

          Button("Open Privacy Settings") {
            controller.openPrivacySettings()
            permissionMonitor.refreshNow()
          }
          .accessibilityIdentifier("AppIdentityOpenPrivacySettingsButton")

          Button("Copy Diagnostics") {
            controller.copyAppDiagnosticsToClipboard()
          }
          .accessibilityIdentifier("AppIdentityCopyDiagnosticsButton")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var advancedPanel: some View {
    SettingsSection(title: "Advanced", systemName: "slider.horizontal.3") {
      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Last source", value: controller.lastSelectionSource.displayName)

        Button("Reset Provider Settings") {
          settings.resetProviderSettings()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var showsMenuBarIcon: Binding<Bool> {
    Binding(
      get: { settings.showsMenuBarIcon },
      set: { newValue in
        guard settings.showsMenuBarIcon != newValue else {
          return
        }
        settings.showsMenuBarIcon = newValue
      }
    )
  }

  private var startAtLogin: Binding<Bool> {
    Binding(
      get: { loginItemStatus.isEnabled },
      set: { newValue in
        do {
          try LoginItemService.setEnabled(newValue)
          refreshLoginItemStatus()
        } catch {
          loginItemStatus = .unavailable(error.localizedDescription)
          AppLog.settings.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
      }
    )
  }

  private var autoCopyMode: Binding<AutoCopyMode> {
    Binding(
      get: { settings.autoCopyMode },
      set: { settings.autoCopyMode = $0 }
    )
  }

  private var loginItemDetailColor: Color {
    loginItemStatus == .requiresApproval ? Color.orange : Color.secondary
  }

  private var appIdentityIconName: String {
    controller.appIdentity.blockingIssue == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
  }

  private var appIdentityColor: Color {
    controller.appIdentity.blockingIssue == nil ? .green : .orange
  }

  private var translateHotKey: Binding<HotKeyConfiguration> {
    Binding(
      get: { settings.translateHotKey },
      set: { settings.translateHotKey = $0 }
    )
  }

  private var ocrHotKey: Binding<HotKeyConfiguration> {
    Binding(
      get: { settings.ocrHotKey },
      set: { settings.ocrHotKey = $0 }
    )
  }

  private var floatingPanelPlacement: Binding<FloatingPanelPlacement> {
    Binding(
      get: { settings.floatingPanelPlacement },
      set: { settings.floatingPanelPlacement = $0 }
    )
  }

  private var translationHistoryLimit: Binding<Int> {
    Binding(
      get: { settings.translationHistoryLimit },
      set: { settings.translationHistoryLimit = $0 }
    )
  }

  private func refreshRuntimeState() {
    controller.refreshAppIdentity()
    permissionMonitor.refreshNow()
    refreshLoginItemStatus()
  }

  private func refreshLoginItemStatus() {
    loginItemStatus = LoginItemService.status
  }

  private func openAccessibilitySettings() {
    PermissionService.openAccessibilitySettings()
    permissionMonitor.refreshNow()
  }

  private func openScreenCaptureSettings() {
    PermissionService.openScreenCaptureSettings()
    permissionMonitor.refreshNow()
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  let systemName: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemName)
        .font(.headline)

      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(nsColor: .separatorColor).opacity(0.48), lineWidth: 1)
    }
  }
}

private struct HotKeySettingsRow: View {
  let title: String
  @Binding var hotKey: HotKeyConfiguration
  let defaultHotKey: HotKeyConfiguration

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
      Spacer()
      HotKeyRecorderButton(hotKey: $hotKey)
        .frame(width: 190, height: 28)
        .id(hotKey.displayString)
      Button("Reset") {
        hotKey = defaultHotKey
      }
      .disabled(hotKey == defaultHotKey)
    }
  }
}

private struct PermissionSettingsRow: View {
  let title: String
  let detail: String
  let isEnabled: Bool?
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .foregroundStyle(iconColor)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isEnabled != true {
        Button("Open") {
          action()
        }
      }
    }
  }

  private var iconName: String {
    if isEnabled == nil {
      return "questionmark.circle"
    }

    return isEnabled == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
  }

  private var iconColor: Color {
    if isEnabled == nil {
      return .secondary
    }

    return isEnabled == true ? .green : .orange
  }
}

private struct AppIdentityDetailRow: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
