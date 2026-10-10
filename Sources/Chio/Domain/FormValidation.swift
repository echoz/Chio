/// Tracks when application-owned validation messages should become visible.
/// Compute current issues in field order, excluding fields that are not shown.
public struct FormValidation<Field: Hashable> {
    private let visitedFields: Set<Field>
    private let hasAttemptedSubmission: Bool

    private enum CodingKeys: String, CodingKey {
        case visitedFields
        case hasAttemptedSubmission = "submissionAttempted"
    }

    public init() {
        visitedFields = []
        hasAttemptedSubmission = false
    }

    private init(visitedFields: Set<Field>, hasAttemptedSubmission: Bool) {
        self.visitedFields = visitedFields
        self.hasAttemptedSubmission = hasAttemptedSubmission
    }

    /// Makes a field's current issue visible after focus leaves that field.
    public func recordingExit(from field: Field) -> Self {
        Self(visitedFields: visitedFields.union([field]), hasAttemptedSubmission: hasAttemptedSubmission)
    }

    /// Returns new visibility state and the first invalid field for native focus.
    /// The receiver and the application's current issues remain unchanged.
    public func submitting(_ issues: [Issue]) -> (validation: Self, firstInvalidField: Field?) {
        (Self(visitedFields: visitedFields, hasAttemptedSubmission: true), issues.first?.field)
    }

    /// Reads the first current issue after the field has been exited or submitted.
    public func message(for field: Field, in issues: [Issue]) -> String? {
        guard hasAttemptedSubmission || visitedFields.contains(field) else { return nil }
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
extension FormValidation: Hashable {}
extension FormValidation: Sendable where Field: Sendable {}
extension FormValidation: Encodable where Field: Encodable {}
extension FormValidation: Decodable where Field: Decodable {}
extension FormValidation.Issue: Equatable {}
extension FormValidation.Issue: Hashable {}
extension FormValidation.Issue: Sendable where Field: Sendable {}
extension FormValidation.Issue: Encodable where Field: Encodable {}
extension FormValidation.Issue: Decodable where Field: Decodable {}
