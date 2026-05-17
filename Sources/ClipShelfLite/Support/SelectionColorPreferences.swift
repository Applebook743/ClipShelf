import AppKit
import SwiftUI

enum SelectionColorPreferences {
    static let changedNotification = Notification.Name("ClipShelfSelectionColorChanged")

    private static let redKey = "selectionColor.red"
    private static let greenKey = "selectionColor.green"
    private static let blueKey = "selectionColor.blue"

    static var color: Color {
        get {
            guard UserDefaults.standard.object(forKey: redKey) != nil else {
                return Color(nsColor: .labelColor).opacity(0.90)
            }

            return Color(
                red: UserDefaults.standard.double(forKey: redKey),
                green: UserDefaults.standard.double(forKey: greenKey),
                blue: UserDefaults.standard.double(forKey: blueKey)
            )
        }
        set {
            let nsColor = NSColor(newValue)
                .usingColorSpace(.deviceRGB)
                ?? NSColor.labelColor

            UserDefaults.standard.set(nsColor.redComponent, forKey: redKey)
            UserDefaults.standard.set(nsColor.greenComponent, forKey: greenKey)
            UserDefaults.standard.set(nsColor.blueComponent, forKey: blueKey)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: redKey)
        UserDefaults.standard.removeObject(forKey: greenKey)
        UserDefaults.standard.removeObject(forKey: blueKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}
