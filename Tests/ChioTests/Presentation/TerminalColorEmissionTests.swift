import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct TerminalColorEmissionTests {
    @Test("The SSH true-color launch environment preserves Chio's authored colors")
    func trueColorEmission() throws {
        let output = try emitThemedText(environment: [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "LANG": "en_US.UTF-8",
        ])

        #expect(output.contains("38;2;242;238;250"))
        #expect(output.contains("48;2;33;29;42"))
        #expect(!output.contains("48;5;59"))
    }

    @Test("Declaring true-color capability still respects NO_COLOR")
    func noColorEmission() throws {
        let output = try emitThemedText(environment: [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "NO_COLOR": "1",
            "LANG": "en_US.UTF-8",
        ])

        #expect(output.contains("Chio"))
        #expect(!output.contains("38;"))
        #expect(!output.contains("48;"))
    }

    private func emitThemedText(environment: [String: String]) throws -> String {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        let surface = DefaultRenderer().render(
            Text("Chio").chioTheme(.default),
            proposal: .init(width: 4, height: 1)
        ).rasterSurface
        let host = TerminalHost(
            inputFileDescriptor: pipe.fileHandleForReading.fileDescriptor,
            outputFileDescriptor: pipe.fileHandleForWriting.fileDescriptor,
            fallbackSize: surface.size,
            capabilityProfile: .detect(environment: environment, isTTY: true),
            environment: environment,
            usesTerminalEditOperations: false
        )
        try host.present(surface)
        // The public write boundary drains queued presentation before writing.
        try host.write("")
        try pipe.fileHandleForWriting.close()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
