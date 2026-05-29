import AppKit
import SwiftUI

struct ProviderAddMenuButton: NSViewRepresentable {
  let providerIDs: [ProviderID]
  let onSelect: (ProviderID) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onSelect: onSelect)
  }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.imagePosition = .imageLeading
    button.identifier = NSUserInterfaceItemIdentifier("ProviderAddMenuButton")
    button.setAccessibilityIdentifier("ProviderAddMenuButton")
    button.setAccessibilityLabel("Add Provider")
    configure(button, coordinator: context.coordinator)
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.onSelect = onSelect
    configure(button, coordinator: context.coordinator)
  }

  private func configure(_ button: NSPopUpButton, coordinator: Coordinator) {
    button.removeAllItems()
    button.addItem(withTitle: "Add Provider")

    if let titleItem = button.item(at: 0) {
      titleItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
        .providerSizedMenuIcon(size: NSSize(width: 13, height: 13), isTemplate: true)
    }

    for providerID in providerIDs {
      button.menu?.addItem(ProviderAddMenuItemFactory.makeProviderItem(
        providerID: providerID,
        target: coordinator,
        action: #selector(Coordinator.selectProvider(_:))
      ))
    }

    button.selectItem(at: 0)
  }

  @MainActor
  final class Coordinator: NSObject {
    var onSelect: (ProviderID) -> Void

    init(onSelect: @escaping (ProviderID) -> Void) {
      self.onSelect = onSelect
    }

    @objc func selectProvider(_ sender: NSMenuItem) {
      guard let rawValue = sender.representedObject as? String,
            let providerID = ProviderID(rawValue: rawValue)
      else {
        return
      }

      onSelect(providerID)
    }
  }
}

enum ProviderAddMenuItemFactory {
  static func makeProviderItem(providerID: ProviderID, target: AnyObject?, action: Selector?) -> NSMenuItem {
    let item = NSMenuItem(title: providerID.displayName, action: action, keyEquivalent: "")
    item.target = target
    item.representedObject = providerID.rawValue
    item.image = providerID.menuIconImage()
    return item
  }
}

private extension NSImage {
  func providerSizedMenuIcon(size: NSSize, isTemplate: Bool) -> NSImage? {
    guard let image = copy() as? NSImage else {
      return nil
    }

    image.size = size
    image.isTemplate = isTemplate
    return image
  }
}
