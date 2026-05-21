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
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          switch controller.selectedMainSection {
          case .dashboard:
            header
            languagePanel
            quickActions
            resultPanel
          case .providers:
            providerPanel
          case .settings:
            DashboardSettingsView(controller: controller)
          }
        }
        .padding(24)
      }
      .navigationTitle(controller.selectedMainSection.title)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 48, height: 48)

      VStack(alignment: .leading, spacing: 4) {
        Text("LexiRay")
          .font(.largeTitle.weight(.semibold))

        Text("Selection, OCR, and LLM translation for macOS.")
          .foregroundStyle(.secondary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        Label(controller.settings.translateHotKey.displayString, systemImage: "keyboard")
        Label(controller.settings.ocrHotKey.displayString, systemImage: "viewfinder")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var quickActions: some View {
    GroupBox("Quick Translate") {
      VStack(alignment: .leading, spacing: 12) {
        TextField("Type text, or select text anywhere and press \(controller.settings.translateHotKey.displayString)", text: $manualText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(3 ... 6)

        HStack(spacing: 10) {
          Button {
            controller.translateManualText(manualText)
          } label: {
            Label("Translate", systemImage: "arrow.right.circle.fill")
          }
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
    GroupBox("Languages") {
      LanguageSettingsView(settings: controller.settings)
    }
  }

  private var resultPanel: some View {
    GroupBox("Recent Result") {
      VStack(alignment: .leading, spacing: 12) {
        switch controller.panelState {
        case .idle:
          ContentUnavailableView("Ready", systemImage: "keyboard", description: Text("Use a hotkey or the quick translate controls."))
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
    GroupBox("Providers") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          LabeledContent("Active", value: activeProviderSummary)
          Spacer()
          LabeledContent(
            "Languages",
            value: "\(controller.settings.language1) <-> \(controller.settings.language2)"
          )
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        ProviderConfigurationList(settings: controller.settings)
      }
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
      return "None"
    }

    return names.joined(separator: ", ")
  }
}
