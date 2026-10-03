import Testing
@testable import Chio

@Suite("Search selection")
struct SearchSelectionTests {
    @Test("A visible selected identity survives source reordering")
    func preservesSelection() {
        #expect(SearchSelection.reconciled(7, visibleIDs: [9, 7, 42]) == 7)
        #expect(SearchSelection.reconciled(7, visibleIDs: [42, 9, 7]) == 7)
    }

    @Test("Missing or absent selection chooses the first visible identity")
    func choosesFirstResult() {
        #expect(SearchSelection.reconciled(7, visibleIDs: [42, 9]) == 42)
        #expect(SearchSelection.reconciled(nil, visibleIDs: [42, 9]) == 42)
    }

    @Test("No results clear selection")
    func clearsSelection() {
        #expect(SearchSelection.reconciled(7, visibleIDs: [Int]()) == nil)
        #expect(SearchSelection.reconciled(nil as Int?, visibleIDs: []) == nil)
    }

    @Test("Filtering and changing data reconcile by identity without restoring old hidden selection")
    func selectionAcrossDataChanges() {
        var selection: String? = "b"
        selection = SearchSelection.reconciled(selection, visibleIDs: ["a", "b", "c"])
        #expect(selection == "b")
        selection = SearchSelection.reconciled(selection, visibleIDs: ["c"])
        #expect(selection == "c")
        selection = SearchSelection.reconciled(selection, visibleIDs: ["a", "b", "c"])
        #expect(selection == "c")
        selection = SearchSelection.reconciled(selection, visibleIDs: [])
        #expect(selection == nil)
        selection = SearchSelection.reconciled(selection, visibleIDs: ["new"])
        #expect(selection == "new")
    }
}
