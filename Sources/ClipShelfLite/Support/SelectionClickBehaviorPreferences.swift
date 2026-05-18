import Foundation

enum SelectionClickBehaviorPreferences {
    static let changedNotification = Notification.Name("ClipShelfSelectionClickBehaviorChanged")

    private static let switchToClickedRecordKey = "selectionClickBehavior.switchToClickedRecord"

    static var switchToClickedRecord: Bool {
        get {
            UserDefaults.standard.bool(forKey: switchToClickedRecordKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: switchToClickedRecordKey)
            NotificationCenter.default.post(name: changedNotification, object: newValue)
        }
    }
}
