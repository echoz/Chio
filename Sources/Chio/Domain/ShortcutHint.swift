/// Display metadata for a shortcut. It does not register or enable an action.
public struct ShortcutHint {
    public let key: String
    public let label: String
    /// Expanded help text; an empty string omits the detail row.
    public let detail: String

    public init(_ key: String, _ label: String, detail: String = "") {
        self.key = key
        self.label = label
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey { case key, label, detail }
}

extension ShortcutHint: Encodable {}

extension ShortcutHint: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(String.self, forKey: .key),
            try container.decode(String.self, forKey: .label),
            detail: try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        )
    }
}

extension ShortcutHint: Hashable {}

extension ShortcutHint: Sendable {}
