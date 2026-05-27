import AppKit
import SwiftUI

struct MainView: View {
  @ObservedObject var controller: LexiRayController
  @State private var manualText = ""

  var body: some View {
    NavigationSplitView {
      List(selection: $controller.selectedMainSection) {
        ForEach(MainSection.allCases) { section in
          Label(section.title, systemImage: section.systemImage)
            .tag(section)
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    } detail: {
      ZStack(alignment: .top) {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            switch controller.selectedMainSection {
            case .dashboard:
              header
              quickActions
              languagePanel
              resultPanel
            case .providers:
              providerPanel
            case .settings:
              DashboardSettingsView(controller: controller)
            }
          }
          .padding(24)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        if let toast = controller.copyToast {
          CopyToastView(toast: toast)
            .padding(.top, 18)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .zIndex(2)
        }
      }
      .navigationTitle(controller.selectedMainSection.title)
      .animation(.easeInOut(duration: 0.16), value: controller.copyToast?.id)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 4) {
        Text("LexiRay")
          .font(.largeTitle.weight(.semibold))

        Text(activeProviderSummary)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 8) {
        DashboardPill(title: controller.settings.languageDirectionLabel(sourceLanguage: nil, targetLanguage: controller.settings.language2), systemName: "arrow.left.arrow.right")
        DashboardPill(title: controller.settings.translateHotKey.displayString, systemName: "keyboard")
        DashboardPill(title: controller.settings.ocrHotKey.displayString, systemName: "viewfinder")
      }
    }
  }

  private var quickActions: some View {
    DashboardCard(title: "Translate", systemName: "text.cursor") {
      VStack(alignment: .leading, spacing: 12) {
        SourceTextEditor(
          text: $manualText,
          placeholder: "Type or edit source text",
          minHeight: 132,
          accessibilityIdentifier: "MainManualSourceEditor"
        )

        HStack(spacing: 10) {
          Button {
            controller.translateManualText(manualText)
          } label: {
            Label("Translate", systemImage: "arrow.right.circle.fill")
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: [.command])
          .disabled(manualText.trimmedForQuery.isEmpty)

          Button {
            controller.translateCurrentSelection()
          } label: {
            Label("Selection", systemImage: "text.viewfinder")
          }

          Button {
            controller.translateOCRRegion()
          } label: {
            Label("OCR Region", systemImage: "viewfinder")
          }

          if !controller.lastOCRText.trimmedForQuery.isEmpty {
            Button {
              controller.translateLastOCRText()
            } label: {
              Label("Last OCR", systemImage: "text.viewfinder")
            }
          }

          Spacer()
        }
      }
    }
  }

  private var languagePanel: some View {
    DashboardCard(title: "Languages", systemName: "globe") {
      LanguageSettingsView(settings: controller.settings)
    }
  }

  private var resultPanel: some View {
    DashboardCard(title: "Recent Result", systemName: "text.bubble") {
      VStack(alignment: .leading, spacing: 12) {
        switch controller.panelState {
        case .idle:
          ContentUnavailableView("Ready", systemImage: "keyboard", description: Text("No recent translation."))
            .frame(maxWidth: .infinity, minHeight: 120)
        case let .loading(state):
          HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 4) {
              Text(state.title)
              if let preview = state.preview?.nonEmptyTrimmed {
                Text(preview)
                  .lineLimit(4)
                  .textSelection(.enabled)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        case let .batch(batch):
          TranslationBatchResultsView(
            controller: controller,
            batch: batch,
            showsSourcePreview: true,
            resultLineLimit: 6,
            compact: true
          )
        case let .result(result):
          TranslationBatchResultsView(
            controller: controller,
            batch: singleResultBatch(result),
            showsSourcePreview: true,
            resultLineLimit: 6,
            compact: true
          )
        case let .error(message):
          ContentUnavailableView("No Translation", systemImage: "exclamationmark.triangle", description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      }
    }
  }

  private var providerPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 10) {
        Label("Providers", systemImage: "server.rack")
          .font(.title2.weight(.semibold))

        Spacer()

        DashboardPill(title: activeProviderSummary, systemName: "bolt.horizontal")
        DashboardPill(title: "\(controller.settings.language1) <-> \(controller.settings.language2)", systemName: "globe")
      }

      ProviderConfigurationList(settings: controller.settings)
    }
  }

  private func singleResultBatch(_ result: TranslationResult) -> TranslationBatch {
    TranslationBatch(
      request: result.request,
      entries: [
        ProviderTranslationEntry(
          providerConfigurationID: result.providerConfigurationID,
          providerID: result.providerID,
          providerName: result.providerName,
          status: .success(result)
        )
      ]
    )
  }

  private var activeProviderSummary: String {
    let names = controller.settings.enabledProviderConfigurations().map(\.effectiveDisplayName)
    if names.isEmpty {
      return "No active provider"
    }

    return names.joined(separator: ", ")
  }
}

private struct DashboardCard<Content: View>: View {
  let title: String
  let systemName: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemName)
        .font(.headline)
        .foregroundStyle(.primary)

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

private struct DashboardPill: View {
  let title: String
  let systemName: String

  var body: some View {
    Label(title, systemImage: systemName)
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.quaternary, in: Capsule())
  }
}
