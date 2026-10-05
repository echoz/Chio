import Chio
import Foundation

/// An editable local settings snapshot, including unfinished hidden input.
struct RunSettingsDraft {
    let name: String
    let automaticRuns: Bool
    let intervalMinutes: String
    let timeoutMinutes: String

    init(name: String = "Chio", automaticRuns: Bool = false,
         intervalMinutes: String = "15", timeoutMinutes: String = "5") {
        self.name = name
        self.automaticRuns = automaticRuns
        self.intervalMinutes = intervalMinutes
        self.timeoutMinutes = timeoutMinutes
    }

    func replacing(name: String? = nil, automaticRuns: Bool? = nil,
                   intervalMinutes: String? = nil, timeoutMinutes: String? = nil) -> Self {
        Self(name: name ?? self.name, automaticRuns: automaticRuns ?? self.automaticRuns,
             intervalMinutes: intervalMinutes ?? self.intervalMinutes,
             timeoutMinutes: timeoutMinutes ?? self.timeoutMinutes)
    }

    var issues: [FormValidation<Field>.Issue] {
        var issues: [FormValidation<Field>.Issue] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            issues.append(.init(field: .name, message: "Enter a workspace name."))
        } else if trimmedName.count > 32 {
            issues.append(.init(field: .name, message: "Use 32 characters or fewer."))
        }
        if automaticRuns {
            let interval = Self.minutes(intervalMinutes)
            let timeout = Self.minutes(timeoutMinutes)
            if interval == nil {
                issues.append(.init(field: .interval, message: "Use whole minutes from 1 to 60."))
            }
            if timeout == nil {
                issues.append(.init(field: .timeout, message: "Use whole minutes from 1 to 60."))
            } else if let interval, let timeout, timeout >= interval {
                issues.append(.init(field: .timeout, message: "Timeout must be shorter than the interval."))
            }
        }
        return issues
    }

    var summary: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return automaticRuns ? "\(name) · every \(intervalMinutes)m, timeout \(timeoutMinutes)m" : "\(name) · manual"
    }

    private static func minutes(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...60).contains(value) else { return nil }
        return value
    }

    enum Field { case name, automaticRuns, interval, timeout }
}

extension RunSettingsDraft: Equatable {}
extension RunSettingsDraft: Hashable {}
extension RunSettingsDraft: Codable {}
extension RunSettingsDraft: Sendable {}
extension RunSettingsDraft.Field: Hashable {}
extension RunSettingsDraft.Field: Codable {}
extension RunSettingsDraft.Field: Sendable {}
