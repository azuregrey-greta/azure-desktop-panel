import Foundation

/// 草稿的唯一落盘位置：UserDefaults（com.azure.smallpanel 域）
final class DraftStore {
    static let key = "AzurePanel_Draft_Content"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDraft() -> String {
        defaults.string(forKey: Self.key) ?? ""
    }

    func saveDraft(_ content: String) {
        if content.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(content, forKey: Self.key)
        }
    }

    func clearDraft() {
        defaults.removeObject(forKey: Self.key)
    }
}
