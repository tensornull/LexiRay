import SwiftUI

struct MainView: View {
  @ObservedObject var controller: LexiRayController
  @State private var manualText = ""

  var body: some View {
    NavigationSplitView {
      List {
        Section("LexiRay") {
          Label("Translate", systemImage: "text.magnifyingglass")
          Label("Settings", systemImage: "slider.horizontal.3")
          Label("Permissions", systemImage: "lock.shield")
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    } detail: {
      VStack(alignment: .leading, spacing: 22) {
        header
        quickQuery
        statusPanel
        Spacer(minLength: 0)
      }
      .padding(28)
      .navigationTitle("LexiRay")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("LexiRay")
        .font(.largeTitle.weight(.semibold))

      Text("Fast selection translation for macOS.")
        .foregroundStyle(.secondary)
    }
  }

  private var quickQuery: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Quick Query")
        .font(.headline)

      HStack(alignment: .top, spacing: 10) {
        TextField("Type text or select text anywhere and press \(AppConstants.defaultHotKeyDescription)", text: $manualText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(3 ... 5)

        Button {
          controller.translateManualText(manualText)
        } label: {
          Label("Translate", systemImage: "arrow.right.circle.fill")
        }
        .disabled(manualText.trimmedForQuery.isEmpty)
        .controlSize(.large)
      }
    }
  }

  private var statusPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Status")
          .font(.headline)

        Spacer()

        Button {
          controller.translateCurrentSelection()
        } label: {
          Label("Translate Selection", systemImage: "keyboard")
        }
      }

      PermissionRow(
        title: "Accessibility",
        detail: PermissionService.isAccessibilityTrusted ? "Enabled" : "Needed for selected text",
        isEnabled: PermissionService.isAccessibilityTrusted,
        action: PermissionService.openAccessibilitySettings
      )

      Divider()

      LabeledContent("Provider", value: controller.settings.preferredProvider.displayName)
      LabeledContent("Target", value: controller.settings.targetLanguage)
      LabeledContent("Last source", value: controller.lastSelectionSource.displayName)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct PermissionRow: View {
  let title: String
  let detail: String
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(isEnabled ? .green : .orange)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if !isEnabled {
        Button("Open") {
          action()
        }
      }
    }
  }
}
