/// Editable choices; limits and current availability are checked when saving.
struct ChoiceDraft {
    let language: Language
    let capabilities: Set<Capability>

    init(language: Language = .swift, capabilities: Set<Capability> = []) {
        self.language = language
        self.capabilities = capabilities
    }

    func replacing(language: Language? = nil, capabilities: Set<Capability>? = nil) -> Self {
        Self(language: language ?? self.language, capabilities: capabilities ?? self.capabilities)
    }

    func validationMessage(availableCapabilities: Set<Capability>) -> String? {
        guard !capabilities.isEmpty else { return "Choose at least 1 capability." }
        guard capabilities.count <= 3 else { return "Choose at most 3 capabilities." }
        let unavailable = Capability.allCases.filter {
            capabilities.contains($0) && !availableCapabilities.contains($0)
        }
        guard unavailable.isEmpty else {
            return "Unavailable: \(unavailable.map(\.label).joined(separator: ", "))."
        }
        return nil
    }

    var summary: String {
        let labels = Capability.allCases.filter { capabilities.contains($0) }.map(\.label)
        return "\(language.label) · \(labels.isEmpty ? "none selected" : labels.joined(separator: ", "))"
    }

    enum Language: String {
        case swift, rust, go, python

        var label: String {
            switch self {
            case .swift: "Swift"
            case .rust: "Rust"
            case .go: "Go"
            case .python: "Python"
            }
        }
    }

    enum Capability: String {
        case build, test, lint, format, docs, deploy

        var label: String {
            switch self {
            case .build: "Build"
            case .test: "Test"
            case .lint: "Lint"
            case .format: "Format"
            case .docs: "Docs"
            case .deploy: "Deploy"
            }
        }

        var description: String {
            switch self {
            case .build: "Compile the project"
            case .test: "Run the test suite"
            case .lint: "Check source quality"
            case .format: "Format source files"
            case .docs: "Generate documentation"
            case .deploy: "Unavailable in this local demo"
            }
        }
    }
}

extension ChoiceDraft: Equatable {}
extension ChoiceDraft: Hashable {}
extension ChoiceDraft: Codable {}
extension ChoiceDraft: Sendable {}
extension ChoiceDraft.Language: CaseIterable {}
extension ChoiceDraft.Language: Identifiable { var id: Self { self } }
extension ChoiceDraft.Language: Hashable {}
extension ChoiceDraft.Language: Codable {}
extension ChoiceDraft.Language: Sendable {}
extension ChoiceDraft.Capability: CaseIterable {}
extension ChoiceDraft.Capability: Identifiable { var id: Self { self } }
extension ChoiceDraft.Capability: Hashable {}
extension ChoiceDraft.Capability: Codable {}
extension ChoiceDraft.Capability: Sendable {}
