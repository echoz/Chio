@testable import ChioDashboard
import Foundation
import Testing

struct RunSettingsDraftTests {
    @Test("Defaults are valid manual settings and replacements preserve the original")
    func replacements() {
        let original = RunSettingsDraft()
        #expect(original == RunSettingsDraft(name: "Chio", automaticRuns: false,
                                             intervalMinutes: "15", timeoutMinutes: "5"))
        #expect(original.issues.isEmpty)
        #expect(original.summary == "Chio · manual")
        #expect(original.replacing() == original)
        #expect(original.replacing(name: "Local").name == "Local")
        #expect(original.replacing(automaticRuns: true) == RunSettingsDraft(automaticRuns: true))
        #expect(original.replacing(intervalMinutes: "") == RunSettingsDraft(intervalMinutes: ""))
        #expect(original.replacing(timeoutMinutes: "unfinished") == RunSettingsDraft(timeoutMinutes: "unfinished"))
        let changed = original.replacing(name: "", automaticRuns: true,
                                         intervalMinutes: "", timeoutMinutes: "")
        #expect(changed.issues.map(\.field) == [.name, .interval, .timeout])
        #expect(original == RunSettingsDraft())
        let custom = RunSettingsDraft(name: "Nightly", automaticRuns: true,
                                      intervalMinutes: "23", timeoutMinutes: "7")
        #expect(custom.replacing(name: "") == RunSettingsDraft(name: "", automaticRuns: true,
                                                               intervalMinutes: "23", timeoutMinutes: "7"))
        #expect(custom.replacing(automaticRuns: false) == RunSettingsDraft(name: "Nightly", automaticRuns: false,
                                                                          intervalMinutes: "23", timeoutMinutes: "7"))
        #expect(custom.replacing(intervalMinutes: "raw") == RunSettingsDraft(name: "Nightly", automaticRuns: true,
                                                                           intervalMinutes: "raw", timeoutMinutes: "7"))
        #expect(custom.replacing(timeoutMinutes: "") == RunSettingsDraft(name: "Nightly", automaticRuns: true,
                                                                        intervalMinutes: "23", timeoutMinutes: ""))
        #expect(custom == RunSettingsDraft(name: "Nightly", automaticRuns: true,
                                           intervalMinutes: "23", timeoutMinutes: "7"))
    }

    @Test("Name rules count trimmed user-perceived characters")
    func names() {
        for name in ["", " ", "\n\t"] {
            #expect(RunSettingsDraft(name: name).issues.map(\.field) == [.name])
        }
        let boundary = " \n" + String(repeating: "👩🏽‍💻", count: 32) + "\t "
        #expect(RunSettingsDraft(name: boundary).issues.isEmpty)
        #expect(RunSettingsDraft(name: boundary + "a").issues.map(\.field) == [.name])
        #expect(RunSettingsDraft(name: "  Local  ").summary == "Local · manual")
    }

    @Test("Malformed and out-of-range minutes identify the edited field",
          arguments: ["", " \n", "one", "1.5", "-1", "0", "61", "999999999999999999999999999999"])
    func malformedMinutes(_ text: String) {
        let interval = RunSettingsDraft(automaticRuns: true, intervalMinutes: text, timeoutMinutes: "1")
        let timeout = RunSettingsDraft(automaticRuns: true, intervalMinutes: "60", timeoutMinutes: text)
        #expect(interval.issues.map(\.field) == [.interval])
        #expect(timeout.issues.map(\.field) == [.timeout])
        #expect(interval.issues.first?.message == "Use whole minutes from 1 to 60.")
        #expect(timeout.issues.first?.message == "Use whole minutes from 1 to 60.")
    }

    @Test("Minute bounds and the strict cross-field rule are distinct")
    func minuteBoundaries() {
        #expect(RunSettingsDraft(automaticRuns: true, intervalMinutes: "2", timeoutMinutes: "1").issues.isEmpty)
        #expect(RunSettingsDraft(automaticRuns: true, intervalMinutes: "60", timeoutMinutes: "59").issues.isEmpty)
        for pair in [("1", "1"), ("60", "60"), ("5", "6")] {
            let draft = RunSettingsDraft(automaticRuns: true, intervalMinutes: pair.0, timeoutMinutes: pair.1)
            #expect(draft.issues.map(\.field) == [.timeout])
            #expect(draft.issues.first?.message == "Timeout must be shorter than the interval.")
        }
        let padded = RunSettingsDraft(automaticRuns: true, intervalMinutes: " 02 ", timeoutMinutes: " 1\n")
        #expect(padded.issues.isEmpty)
        #expect(padded.intervalMinutes == " 02 " && padded.timeoutMinutes == " 1\n")
    }

    @Test("Changing either related value recomputes the current cross-field issue")
    func crossFieldUpdates() {
        let invalid = RunSettingsDraft(automaticRuns: true, intervalMinutes: "5", timeoutMinutes: "5")
        #expect(invalid.issues.map(\.field) == [.timeout])
        #expect(invalid.replacing(intervalMinutes: "6").issues.isEmpty)
        #expect(invalid.replacing(timeoutMinutes: "4").issues.isEmpty)
        #expect(invalid.issues.map(\.field) == [.timeout])
        #expect(invalid.replacing(intervalMinutes: "bad").issues.map(\.field) == [.interval])
        #expect(invalid.replacing(intervalMinutes: "bad", timeoutMinutes: "bad").issues.map(\.field) == [.interval, .timeout])
    }

    @Test("Manual mode excludes hidden rules without repairing unfinished input")
    func hiddenValues() {
        let invalid = RunSettingsDraft(name: "Local", automaticRuns: true,
                                       intervalMinutes: " unfinished ", timeoutMinutes: "0")
        let hidden = invalid.replacing(automaticRuns: false)
        #expect(hidden.issues.isEmpty)
        #expect(hidden.intervalMinutes == invalid.intervalMinutes)
        #expect(hidden.timeoutMinutes == invalid.timeoutMinutes)
        #expect(hidden.replacing(automaticRuns: true) == invalid)
        #expect(hidden.replacing(name: " ").issues.map(\.field) == [.name])
        #expect(invalid.issues.map(\.field) == [.interval, .timeout])
    }

    @Test("Codecs preserve raw editable values and current validation rules")
    func codecs() throws {
        let original = RunSettingsDraft(name: "  Local  ", automaticRuns: true,
                                        intervalMinutes: "unfinished", timeoutMinutes: " 61 ")
        let decoded = try JSONDecoder().decode(RunSettingsDraft.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(Set([original, decoded]).count == 1)
        #expect(decoded.issues.map(\.field) == [.interval, .timeout])
        #expect(decoded.replacing(automaticRuns: false).issues.isEmpty)
        let malformed = Data(#"{"name":"Local","automaticRuns":true,"intervalMinutes":15,"timeoutMinutes":"5"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RunSettingsDraft.self, from: malformed) }
        for field in [RunSettingsDraft.Field.name, .automaticRuns, .interval, .timeout] {
            #expect(try JSONDecoder().decode(RunSettingsDraft.Field.self, from: JSONEncoder().encode(field)) == field)
        }
    }
}
