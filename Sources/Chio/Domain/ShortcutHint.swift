/// Display metadata for a shortcut. It does not register or enable an action.
public struct ShortcutHint {
    public let key: String
    public let label: String
    public let detail: String?

    public init(_ key: String, _ label: String, detail: String? = nil) {
        self.key = key
        self.label = label
        self.detail = detail
    }
}

extension ShortcutHint: Codable {}

extension ShortcutHint: Hashable {}

extension ShortcutHint: Sendable {}
