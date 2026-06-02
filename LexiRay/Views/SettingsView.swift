import SwiftUI

struct DashboardSettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var controller: LexiRayController
  @ObservedObject private var settings: SettingsStore
  @State private var permissions = PermissionStatus.current
  @State private var loginItemStatus = LoginItemService.status

  init(controller: LexiRayController) {
    self.controller = controller
    settings = controller.settings
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      appPanel
      translationPanel
      hotKeyPanel
      floatingPanel
      historyPanel
      permissionPanel
      advancedPanel
    }
    .onAppear(perform: refreshRuntimeState)
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
          detail: permissions.isAccessibilityTrusted ? "Enabled" : "Needed for selected text",
          isEnabled: permissions.isAccessibilityTrusted,
          action: PermissionService.openAccessibilitySettings
        )

        PermissionSettingsRow(
          title: "Screen Recording",
          detail: permissions.isScreenCaptureTrusted ? "Enabled" : "Needed for OCR",
          isEnabled: permissions.isScreenCaptureTrusted,
          action: PermissionService.openScreenCaptureSettings
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
    refreshPermissions()
    refreshLoginItemStatus()
  }

  private func refreshPermissions() {
    permissions = .current
  }

  private func refreshLoginItemStatus() {
    loginItemStatus = LoginItemService.status
  }
}

private struct PermissionStatus: Equatable {
  let isAccessibilityTrusted: Bool
  let isScreenCaptureTrusted: Bool

  static var current: PermissionStatus {
    PermissionStatus(
      isAccessibilityTrusted: PermissionService.isAccessibilityTrusted,
      isScreenCaptureTrusted: PermissionService.isScreenCaptureTrusted
    )
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
