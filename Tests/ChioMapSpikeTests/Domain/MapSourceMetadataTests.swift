@testable import ChioMapSpike
import Foundation
import Testing

struct MapSourceMetadataTests {
    @Test("Required credits and provenance reject blank, oversized and control-bearing values")
    func checkedText() throws {
        let url = try #require(URL(string: "https://example.test/source"))
        for text in ["", "   ", "Credit\nsecond line", "Credit\u{7f}", String(repeating: "x", count: 1_025)] {
            #expect(throws: MapSourceMetadata.ValidationError.invalidText) {
                try MapSourceMetadata(attribution: text, license: "License", licenseURL: url,
                                      sourceURL: url, sourceRevision: "snapshot-1")
            }
            #expect(throws: MapSourceMetadata.ValidationError.invalidText) {
                try MapSourceMetadata(attribution: "Credit", license: text, licenseURL: url,
                                      sourceURL: url, sourceRevision: "snapshot-1")
            }
            #expect(throws: MapSourceMetadata.ValidationError.invalidText) {
                try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: url,
                                      sourceURL: url, sourceRevision: text)
            }
        }
    }

    @Test("Metadata validates every URL and preserves meaningful absence of an attribution link")
    func checkedURLsAndDecoding() throws {
        let validURL = try #require(URL(string: "https://example.test/source"))
        let metadata = try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: validURL,
                                             sourceURL: validURL, sourceRevision: "snapshot-1")
        #expect(metadata.attributionURL == nil)
        let encoded = try JSONEncoder().encode(metadata)
        #expect(try JSONDecoder().decode(MapSourceMetadata.self, from: encoded) == metadata)
        for string in ["relative", "file:///tmp/source", "https://user:secret@example.test/source"] {
            let invalidURL = try #require(URL(string: string))
            #expect(throws: MapSourceMetadata.ValidationError.invalidURL) {
                try MapSourceMetadata(attribution: "Credit", attributionURL: invalidURL, license: "License",
                                      licenseURL: validURL, sourceURL: validURL, sourceRevision: "snapshot-1")
            }
            #expect(throws: MapSourceMetadata.ValidationError.invalidURL) {
                try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: invalidURL,
                                      sourceURL: validURL, sourceRevision: "snapshot-1")
            }
            #expect(throws: MapSourceMetadata.ValidationError.invalidURL) {
                try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: validURL,
                                      sourceURL: invalidURL, sourceRevision: "snapshot-1")
            }
        }
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["attribution", "license", "sourceRevision"] {
            var invalid = object
            invalid[key] = " "
            let input = try JSONSerialization.data(withJSONObject: invalid)
            #expect(throws: MapSourceMetadata.ValidationError.invalidText) {
                try JSONDecoder().decode(MapSourceMetadata.self, from: input)
            }
            invalid.removeValue(forKey: key)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(MapSourceMetadata.self, from: JSONSerialization.data(withJSONObject: invalid))
            }
        }
        for key in ["attributionURL", "licenseURL", "sourceURL"] {
            var invalid = object
            invalid[key] = "file:///tmp/source"
            #expect(throws: MapSourceMetadata.ValidationError.invalidURL) {
                try JSONDecoder().decode(MapSourceMetadata.self, from: JSONSerialization.data(withJSONObject: invalid))
            }
        }
    }
}
