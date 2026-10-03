/// Tracks when application-owned validation messages should become visible.
/// Compute current issues in field order, excluding fields that are not shown.
public struct FormValidation<Field: Hashable> {
    private var visitedFields: Set<Field> = []
    private var submissionAttempted = false

    public init() {}

    /// Makes a field's current issue visible after focus leaves that field.
    public mutating func recordExit(from field: Field) {
        visitedFields.insert(field)
    }

    /// Reveals current issues and returns the first invalid field for native focus.
    @discardableResult
    public mutating func submit(_ issues: [Issue]) -> Field? {
        submissionAttempted = true
        return issues.first?.field
    }

    /// Reads the first current issue after the field has been exited or submitted.
    public func message(for field: Field, in issues: [Issue]) -> String? {
        guard submissionAttempted || visitedFields.contains(field) else { return nil }
        return issues.first { $0.field == field }?.message
    }

    public struct Issue {
        public let field: Field
        public let message: String

        public init(field: Field, message: String) {
            self.field = field
            self.message = message
        }
    }
}

extension FormValidation: Equatable {}
extension FormValidation: Sendable where Field: Sendable {}
extension FormValidation.Issue: Equatable {}
extension FormValidation.Issue: Sendable where Field: Sendable {}
