import Chio
import SwiftTUI

/// The example application's theme choices, separate from Chio's open theme values.
enum ExampleTheme: String {
    case `default`
    case light
    case btop

    var theme: ChioTheme {
        switch self {
        case .default: .default
        case .light: .light
        case .btop: .btop
        }
    }

    var next: Self {
        switch self {
        case .default: .light
        case .light: .btop
        case .btop: .default
        }
    }
}

extension ExampleTheme: CaseIterable {}
extension ExampleTheme: ExpressibleByArgument {}
extension ExampleTheme: Hashable {}
extension ExampleTheme: Codable {}
extension ExampleTheme: Sendable {}
