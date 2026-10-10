/// Accepts native membership changes only for currently visible, enabled IDs.
/// Hidden, removed, and disabled selections remain owned by the application.
enum ChecklistSelection {
    static func applying<ID: Hashable>(
        _ proposed: Set<ID>, to current: Set<ID>, editableIDs: Set<ID>
    ) -> Set<ID> {
        current.subtracting(editableIDs).union(proposed.intersection(editableIDs))
    }
}
