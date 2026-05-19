import AppKit
import SwiftUI

enum AppIconChoice: Int, CaseIterable, Identifiable {
    case clipboardHistory = 1
    case historyList = 2
    case stackedHistory = 3
    case compactClipboard = 4

    var id: Int { rawValue }

    var title: String {
        "方案 \(rawValue)"
    }

    var resourceName: String {
        "AppIcon\(rawValue)"
    }

    var previewImage: NSImage? {
        AppIconPreferences.image(for: self)
    }
}

enum AppIconPreferences {
    static let changedNotification = Notification.Name("AppIconPreferences.changed")
    private static let selectedKey = "appIcon.selected"

    static var selected: AppIconChoice {
        get {
            AppIconChoice(rawValue: UserDefaults.standard.integer(forKey: selectedKey)) ?? .clipboardHistory
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedKey)
            apply(newValue)
            NotificationCenter.default.post(name: changedNotification, object: newValue)
        }
    }

    static func applySavedChoice() {
        apply(selected)
    }

    static func apply(_ choice: AppIconChoice) {
        NSApp.applicationIconImage = dockImage(for: choice)
    }

    static func image(for choice: AppIconChoice) -> NSImage? {
        if let url = Bundle.main.url(forResource: choice.resourceName, withExtension: "icns") {
            return NSImage(contentsOf: url)
        }

        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }

        return nil
    }

    static func dockImage(for choice: AppIconChoice) -> NSImage? {
        guard let image = image(for: choice)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 128, height: 128)
        return image
    }

    static func statusBarImage(for choice: AppIconChoice) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppStatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
