import Chio
import Foundation
import SwiftTUIRuntime
import Testing

struct ChioSyntaxColorsTests {
    @Test("Syntax customization preserves the original theme and unrelated components")
    func replacementIsolation() {
        let base = ChioTheme.light
        let copy = base
        let first = base.replacing(syntax: base.syntax.replacing(keyword: .red))
        let changed = first.replacing(syntax: first.syntax.replacing(comment: .blue))

        #expect(base == copy)
        #expect(changed.syntax.keyword == .red)
        #expect(changed.syntax.comment == .blue)
        #expect(changed.syntax.type == base.syntax.type)
        #expect(changed.syntax.string == base.syntax.string)
        #expect(changed.syntax.number == base.syntax.number)
        #expect(changed.colors == base.colors)
        #expect(changed.spacing == base.spacing)
        #expect(changed.treatments == base.treatments)
        #expect(first.syntax.comment == base.syntax.comment)
        #expect(changed.replacing() == changed)
        #expect(changed.syntax.replacing() == changed.syntax)
        #expect(changed.replacing(colors: changed.colors.replacing(accent: .blue)).syntax == changed.syntax)
    }

    @Test("Every syntax role can be replaced and round-trips through native Color Codable")
    func allRolesRoundTrip() throws {
        let expected = ChioTheme.SyntaxColors(
            keyword: Color(hexRGB: 0x010203), type: Color(hexRGB: 0x040506),
            string: Color(hexRGB: 0x070809), number: Color(hexRGB: 0x101112),
            comment: Color(hexRGB: 0x131415)
        )
        let changed = ChioTheme.default.syntax.replacing(
            keyword: expected.keyword, type: expected.type, string: expected.string,
            number: expected.number, comment: expected.comment
        )
        #expect(changed == expected)
        let encoded = try JSONEncoder().encode(changed)
        let decoded = try JSONDecoder().decode(ChioTheme.SyntaxColors.self, from: encoded)
        #expect(decoded == expected)
        #expect(Set([changed, decoded]).count == 1)
        #expect(Set([changed, changed.replacing(number: .red)]).count == 2)
    }

    @Test("All presets distinguish syntax roles from plain code",
          arguments: [ChioTheme.default, .light, .btop])
    func presetRoles(theme: ChioTheme) {
        let colors = [theme.syntax.keyword, theme.syntax.type, theme.syntax.string,
                      theme.syntax.number, theme.syntax.comment]
        #expect(colors.allSatisfy { $0 != theme.colors.foreground })
        #expect(Set(colors).count == colors.count)
    }
}
