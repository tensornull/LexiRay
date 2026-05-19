import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: SettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        GroupBox("App") {
          Toggle("Show menu bar icon", isOn: showsMenuBarIcon)
        }

        GroupBox("Translation") {
          VStack(alignment: .leading, spacing: 12) {
            LanguageSettingsView(settings: settings, compact: true)
          }
        }

        GroupBox("Providers") {
          ProviderConfigurationList(settings: settings, compact: true)
        }

        GroupBox("Permissions") {
          VStack(alignment: .leading, spacing: 12) {
            PermissionSettingsRow(
              title: "Accessibility",
              isEnabled: PermissionService.isAccessibilityTrusted,
              systemImage: PermissionService.isAccessibilityTrusted ? "checkmark.circle.fill" : "lock.shield",
              action: PermissionService.openAccessibilitySettings
            )

            PermissionSettingsRow(
              title: "Screen Recording",
              isEnabled: PermissionService.isScreenCaptureTrusted,
              systemImage: PermissionService.isScreenCaptureTrusted ? "checkmark.circle.fill" : "rectangle.on.rectangle",
              action: PermissionService.openScreenCaptureSettings
            )

            PermissionSettingsRow(
              title: "Automation",
              status: .unknown,
              systemImage: "applescript",
              action: PermissionService.openAutomationSettings
            )
          }
        }

        Button("Reset Provider Settings") {
          settings.resetProviderSettings()
        }
      }
      .padding(20)
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

}

private struct PermissionSettingsRow: View {
  let title: String
  var isEnabled: Bool?
  var status: PermissionStatus?
  let systemImage: String
  let action: () -> Void

  var body: some View {
    HStack {
      Label(title, systemImage: systemImage)
        .foregroundStyle(effectiveStatus == .enabled ? .primary : .secondary)
      Spacer()
      Button("Open Settings") {
        action()
      }
    }
  }

  private var effectiveStatus: PermissionStatus {
    if let status {
      return status
    }

    return isEnabled == true ? .enabled : .needed
  }
}

private enum PermissionStatus {
  case enabled
  case needed
  case unknown
}
