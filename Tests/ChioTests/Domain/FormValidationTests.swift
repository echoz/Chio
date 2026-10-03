import Chio
import Testing

struct FormValidationTests {
    private enum Field: Hashable, Sendable { case name, model, budget }
    private typealias Validation = FormValidation<Field>

    @Test("Errors appear only after a field exit or a submission attempt")
    func visibilityTiming() {
        var validation = Validation()
        let issues = [Validation.Issue(field: .name, message: "Required"),
                      Validation.Issue(field: .budget, message: "Positive")]
        #expect(validation.message(for: .name, in: issues) == nil)
        validation.recordExit(from: .name)
        #expect(validation.message(for: .name, in: issues) == "Required")
        #expect(validation.message(for: .budget, in: issues) == nil)
        #expect(validation.submit(issues) == .name)
        #expect(validation.message(for: .budget, in: issues) == "Positive")
    }

    @Test("Submission and duplicate messages preserve application issue order")
    func issueOrder() {
        var validation = Validation()
        let issues = [Validation.Issue(field: .budget, message: "First budget rule"),
                      Validation.Issue(field: .name, message: "Name rule"),
                      Validation.Issue(field: .budget, message: "Second budget rule")]
        #expect(validation.submit(issues) == .budget)
        #expect(validation.message(for: .budget, in: issues) == "First budget rule")
        #expect(validation.submit(Array(issues.reversed())) == .budget)
        #expect(validation.message(for: .budget, in: Array(issues.reversed())) == "Second budget rule")
        #expect(validation.submit([issues[1], issues[0]]) == .name)
    }

    @Test("Fixed values, changed rules, and hidden fields never retain stale issues")
    func currentIssuesOnly() {
        var validation = Validation()
        let invalid = [Validation.Issue(field: .budget, message: "Too low")]
        validation.recordExit(from: .budget)
        #expect(validation.message(for: .budget, in: invalid) == "Too low")
        #expect(validation.message(for: .budget, in: []) == nil)
        let changed = [Validation.Issue(field: .budget, message: "Too high")]
        #expect(validation.message(for: .budget, in: changed) == "Too high")
        #expect(validation.submit(invalid) == .budget)
        // The application excludes a hidden budget field from its current issues.
        let visible = [Validation.Issue(field: .name, message: "Required")]
        #expect(validation.submit(visible) == .name)
        #expect(validation.message(for: .budget, in: visible) == nil)
        #expect(validation.submit([]) == nil)
        #expect(validation.message(for: .name, in: []) == nil)
    }

    @Test("A valid submission still reveals issues added by later edits")
    func validSubmission() {
        var validation = Validation()
        #expect(validation.submit([]) == nil)
        #expect(validation.message(for: .model, in: [.init(field: .model, message: "Choose one")])
            == "Choose one")
    }

    @Test("Validation values have independent exit histories")
    func valueSemantics() {
        var first = Validation()
        var copy = first
        first.recordExit(from: .name)
        #expect(first != copy)
        copy.recordExit(from: .name)
        #expect(first == copy)
        first.submit([])
        #expect(first != copy)
    }
}
