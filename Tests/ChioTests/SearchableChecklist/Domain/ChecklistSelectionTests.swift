@testable import Chio
import Testing

struct ChecklistSelectionTests {
    @Test("Visible editable changes preserve hidden, removed and disabled membership")
    func membershipBoundary() {
        let original: Set = ["hidden", "removed", "disabled", "visible"]
        let result = ChecklistSelection.applying(
            ["new", "forbidden"], to: original, editableIDs: ["visible", "new"]
        )
        #expect(result == ["hidden", "removed", "disabled", "new"])
        #expect(original == ["hidden", "removed", "disabled", "visible"])
    }

    @Test("No editable results leave the authoritative selection unchanged")
    func noResults() {
        #expect(ChecklistSelection.applying(["b"], to: ["a"], editableIDs: []) == ["a"])
    }
}
