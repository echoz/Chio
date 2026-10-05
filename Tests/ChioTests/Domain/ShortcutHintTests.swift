import Chio
import Foundation
import Testing

struct ShortcutHintTests {
    @Test("Shortcut descriptors retain authored strings and optional detail")
    func descriptorValues() {
        let hint = ShortcutHint("Ctrl-K", "Commands", detail: "Available on results")
        #expect(hint.key == "Ctrl-K")
        #expect(hint.label == "Commands")
        #expect(hint.detail == "Available on results")
        #expect(ShortcutHint("", "").detail == nil)
        #expect(ShortcutHint("", "", detail: "").detail == "")
        #expect(ShortcutHint("q", "Quit") != ShortcutHint("q", "Quit", detail: ""))
    }

    @Test("Coding preserves group order, duplicate descriptors and absent versus empty detail")
    func coding() throws {
        let groups = [
            ShortcutGroup("Navigation", shortcuts: [
                ShortcutHint("界", "Move", detail: "Wide key"),
                ShortcutHint("q", "Quit"),
                ShortcutHint("q", "Quit"),
                ShortcutHint("q", "Quit", detail: ""),
            ]),
            ShortcutGroup("Empty", shortcuts: []),
        ]
        let encoded = try JSONEncoder().encode(groups)
        let decoded = try JSONDecoder().decode([ShortcutGroup].self, from: encoded)
        #expect(decoded == groups)
        #expect(decoded[0].shortcuts.count == 4)
        let objects = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        #expect(objects[0]["title"] as? String == "Navigation")
        let hints = try #require(objects[0]["shortcuts"] as? [[String: Any]])
        #expect(hints[0]["key"] as? String == "界")
        #expect(hints[0]["label"] as? String == "Move")
        #expect(hints[0]["detail"] as? String == "Wide key")
        #expect(hints[1]["detail"] == nil)
        #expect(hints[3]["detail"] as? String == "")
    }
}
