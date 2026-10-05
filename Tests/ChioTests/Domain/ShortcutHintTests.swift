import Chio
import Foundation
import Testing

struct ShortcutHintTests {
    @Test("Shortcut descriptors retain authored strings with one empty detail value")
    func descriptorValues() {
        let hint = ShortcutHint("Ctrl-K", "Commands", detail: "Available on results")
        #expect(hint.key == "Ctrl-K")
        #expect(hint.label == "Commands")
        #expect(hint.detail == "Available on results")
        #expect(ShortcutHint("", "").detail == "")
        #expect(ShortcutHint("", "", detail: "").detail == "")
        #expect(ShortcutHint("q", "Quit") == ShortcutHint("q", "Quit", detail: ""))
        #expect(Set([ShortcutHint("q", "Quit"), ShortcutHint("q", "Quit", detail: "")]).count == 1)
        #expect(ShortcutHint("q", "Quit", detail: " ").detail == " ")
    }

    @Test("Coding preserves group order, duplicate descriptors and canonical detail strings")
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
        #expect(hints[1]["detail"] as? String == "")
        #expect(hints[2]["detail"] as? String == "")
        #expect(hints[3]["detail"] as? String == "")
    }

    @Test("Historical missing or null detail decodes to the canonical empty string",
          arguments: [#"{"key":"q","label":"Quit"}"#,
                      #"{"key":"q","label":"Quit","detail":null}"#,
                      #"{"key":"q","label":"Quit","detail":""}"#,
                      #"{"key":"q","label":"Quit","unknown":true}"#])
    func historicalDetail(fixture: String) throws {
        let decoded = try JSONDecoder().decode(ShortcutHint.self, from: Data(fixture.utf8))
        #expect(decoded == ShortcutHint("q", "Quit"))
        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object.count == 3)
        #expect(object["key"] as? String == "q")
        #expect(object["label"] as? String == "Quit")
        #expect(object["detail"] as? String == "")
    }

    @Test("Nonempty decoded detail retains authored whitespace")
    func authoredDetail() throws {
        let fixture = #"{"key":"q","label":"Quit","detail":"  Available on results  "}"#
        let decoded = try JSONDecoder().decode(ShortcutHint.self, from: Data(fixture.utf8))
        #expect(decoded == ShortcutHint("q", "Quit", detail: "  Available on results  "))
        #expect(try JSONDecoder().decode(ShortcutHint.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test("Malformed detail is rejected rather than normalized", arguments: ["17", "false", "[]", "{}"])
    func malformedDetail(detail: String) {
        let fixture = "{\"key\":\"q\",\"label\":\"Quit\",\"detail\":\(detail)}"
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ShortcutHint.self, from: Data(fixture.utf8))
        }
    }

    @Test("Key and label remain required string values",
          arguments: [#"{"label":"Quit"}"#,
                      #"{"key":null,"label":"Quit"}"#,
                      #"{"key":17,"label":"Quit"}"#,
                      #"{"key":"q"}"#,
                      #"{"key":"q","label":null}"#,
                      #"{"key":"q","label":false}"#])
    func requiredMetadata(fixture: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ShortcutHint.self, from: Data(fixture.utf8))
        }
    }
}
