import AppKit
import SwiftUI

enum AppIconChoice: Int, CaseIterable, Identifiable {
    case clipboardTextClock = 1
    case clipboardLinesClock = 2
    case stackedWindowsClock = 3

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
            AppIconChoice(rawValue: UserDefaults.standard.integer(forKey: selectedKey)) ?? .clipboardTextClock
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
        NSApp.applicationIconImage = image(for: choice)
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
}
