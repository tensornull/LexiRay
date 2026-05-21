import SwiftUI

struct DashboardSettingsView: View {
  @ObservedObject var controller: LexiRayController

  private var settings: SettingsStore {
    controller.settings
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      appPanel
      hotKeyPanel
      floatingPanel
      permissionPanel
      advancedPanel
    }
  }

  private var appPanel: some View {
    SettingsSection(title: "App", systemName: "app.badge") {
      Toggle("Show menu bar icon", isOn: showsMenuBarIcon)
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

  private var permissionPanel: some View {
    SettingsSection(title: "Permissions", systemName: "lock.shield") {
      VStack(alignment: .leading, spacing: 10) {
        PermissionSettingsRow(
          title: "Accessibility",
          detail: PermissionService.isAccessibilityTrusted ? "Enabled" : "Needed for selected text",
          isEnabled: PermissionService.isAccessibilityTrusted,
          action: PermissionService.openAccessibilitySettings
        )

        PermissionSettingsRow(
          title: "Screen Recording",
          detail: PermissionService.isScreenCaptureTrusted ? "Enabled" : "Needed for OCR",
          isEnabled: PermissionService.isScreenCaptureTrusted,
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
