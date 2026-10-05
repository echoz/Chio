@testable import Chio
import Foundation
import Testing

struct FileExtensionFilterTests {
    @Test("Unrestricted, empty and explicit extension filters have distinct meanings")
    func membership() {
        #expect(FileExtensionFilter.all.allows("swift"))
        #expect(FileExtensionFilter.all.allows(""))
        #expect(!FileExtensionFilter.only([]).allows("swift"))
        #expect(!FileExtensionFilter.only([]).allows(""))
        let sourceFiles = FileExtensionFilter.only(["sWiFt", "md"])
        #expect(sourceFiles.allows("SWIFT"))
        #expect(sourceFiles.allows("MD"))
        #expect(!sourceFiles.allows("txt"))
        #expect(!sourceFiles.allows(""))
        #expect(FileExtensionFilter.only([""]).allows(""))
        // Matching does not silently strip dots or whitespace from authored values.
        #expect(!FileExtensionFilter.only([".swift", " swift "]).allows("swift"))
    }

    @Test("Coding preserves explicit extension alternatives and authored sets")
    func coding() throws {
        let fixtures: [(String, FileExtensionFilter)] = [
            (#"{"all":{}}"#, .all),
            (#"{"only":{"_0":[]}}"#, .only([])),
            (#"{"only":{"_0":["SWIFT",""]}}"#, .only(["SWIFT", ""])),
        ]
        for (json, expected) in fixtures {
            let decoded = try JSONDecoder().decode(FileExtensionFilter.self, from: Data(json.utf8))
            #expect(decoded == expected)
            #expect(Set([decoded, expected]).count == 1)
            let encoded = try JSONEncoder().encode(decoded)
            #expect(try JSONDecoder().decode(FileExtensionFilter.self, from: encoded) == expected)
        }
        for malformed in [#"{"unknown":{}}"#, #"{"only":{}}"#, #"{"only":{"_0":[3]}}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(FileExtensionFilter.self, from: Data(malformed.utf8))
            }
        }
    }
}
