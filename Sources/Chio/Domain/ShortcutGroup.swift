/// An ordered group of shortcut descriptions for keyboard help.
public struct ShortcutGroup {
    public let title: String
    public let shortcuts: [ShortcutHint]

    public init(_ title: String, shortcuts: [ShortcutHint]) {
        self.title = title
        self.shortcuts = shortcuts
    }
}

extension ShortcutGroup: Codable {}

extension ShortcutGroup: Hashable {}

extension ShortcutGroup: Sendable {}
