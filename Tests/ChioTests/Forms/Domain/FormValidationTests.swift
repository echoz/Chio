import Chio
import Foundation
import Testing

struct FormValidationTests {
    private enum Field: Hashable, Codable, Sendable { case name, model, budget }
    private typealias Validation = FormValidation<Field>

    @Test("Errors appear only after a field exit or a submission attempt")
    func visibilityTiming() {
        let initial = Validation()
        let issues = [Validation.Issue(field: .name, message: "Required"),
                      Validation.Issue(field: .budget, message: "Positive")]
        #expect(initial.message(for: .name, in: issues) == nil)
        let visited = initial.recordingExit(from: .name)
        #expect(visited.message(for: .name, in: issues) == "Required")
        #expect(visited.message(for: .budget, in: issues) == nil)
        let submission = visited.submitting(issues)
        #expect(submission.firstInvalidField == .name)
        #expect(submission.validation.message(for: .budget, in: issues) == "Positive")
        #expect(initial.message(for: .name, in: issues) == nil)
        #expect(visited.message(for: .budget, in: issues) == nil)
    }

    @Test("Submission and duplicate messages preserve application issue order")
    func issueOrder() {
        let initial = Validation()
        let issues = [Validation.Issue(field: .budget, message: "First budget rule"),
                      Validation.Issue(field: .name, message: "Name rule"),
                      Validation.Issue(field: .budget, message: "Second budget rule")]
        let submission = initial.submitting(issues)
        #expect(submission.firstInvalidField == .budget)
        #expect(submission.validation.message(for: .budget, in: issues) == "First budget rule")
        let reversed = Array(issues.reversed())
        #expect(initial.submitting(reversed).firstInvalidField == .budget)
        #expect(submission.validation.message(for: .budget, in: reversed) == "Second budget rule")
        #expect(initial.submitting([issues[1], issues[0]]).firstInvalidField == .name)
    }

    @Test("Fixed values, changed rules, and hidden fields never retain stale issues")
    func currentIssuesOnly() {
        let visited = Validation().recordingExit(from: .budget)
        let invalid = [Validation.Issue(field: .budget, message: "Too low")]
        #expect(visited.message(for: .budget, in: invalid) == "Too low")
        #expect(visited.message(for: .budget, in: []) == nil)
        let changed = [Validation.Issue(field: .budget, message: "Too high")]
        #expect(visited.message(for: .budget, in: changed) == "Too high")
        let submitted = visited.submitting(invalid)
        #expect(submitted.firstInvalidField == .budget)
        // The application excludes a hidden budget field from its current issues.
        let visible = [Validation.Issue(field: .name, message: "Required")]
        #expect(submitted.validation.submitting(visible).firstInvalidField == .name)
        #expect(submitted.validation.message(for: .budget, in: visible) == nil)
        #expect(submitted.validation.submitting([]).firstInvalidField == nil)
        #expect(submitted.validation.message(for: .name, in: []) == nil)
    }

    @Test("A valid submission still reveals issues added by later edits")
    func validSubmission() {
        let initial = Validation()
        let submission = initial.submitting([])
        let laterIssues = [Validation.Issue(field: .model, message: "Choose one")]
        #expect(submission.firstInvalidField == nil)
        #expect(submission.validation.message(for: .model, in: laterIssues) == "Choose one")
        #expect(initial.message(for: .model, in: laterIssues) == nil)
    }

    @Test("Independent transformations retain value equality and hash behavior")
    func valueSemantics() {
        let initial = Validation()
        let visited = initial.recordingExit(from: .name)
        #expect(initial != visited)
        #expect(visited == initial.recordingExit(from: .name))
        #expect(visited.recordingExit(from: .name) == visited)
        let submitted = visited.submitting([]).validation
        #expect(visited != submitted)
        #expect(Set([initial, visited, initial.recordingExit(from: .name), submitted]).count == 3)
    }

    @Test("Encoding preserves visibility history without storing current validation rules")
    func coding() throws {
        let issues = [Validation.Issue(field: .name, message: "Required"),
                      Validation.Issue(field: .budget, message: "Positive")]
        let visited = Validation().recordingExit(from: .name)
        for original in [Validation(), visited, visited.submitting(issues).validation] {
            let encoded = try JSONEncoder().encode(original)
            let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(fields["submissionAttempted"] is Bool)
            #expect(fields["hasAttemptedSubmission"] == nil)
            let decoded = try JSONDecoder().decode(Validation.self, from: encoded)
            #expect(decoded == original)
            for field in [Field.name, .budget] {
                #expect(decoded.message(for: field, in: issues) == original.message(for: field, in: issues))
            }
        }
        let historical = Data(#"{"visitedFields":[],"submissionAttempted":true}"#.utf8)
        let decodedHistorical = try JSONDecoder().decode(Validation.self, from: historical)
        #expect(decodedHistorical.message(for: .name, in: issues) == "Required")
        #expect(try JSONDecoder().decode([Validation.Issue].self, from: JSONEncoder().encode(issues)) == issues)
    }
}
