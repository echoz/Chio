/// Keeps selection attached to identity as filtering or source data changes.
enum SearchSelection {
    static func reconciled<ID: Hashable>(_ selection: ID?, visibleIDs: [ID]) -> ID? {
        if let selection, visibleIDs.contains(selection) { return selection }
        return visibleIDs.first
    }
}
