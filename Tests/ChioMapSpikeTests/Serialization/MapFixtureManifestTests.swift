@testable import ChioMapSpike
import Foundation
import Testing

struct MapFixtureManifestTests {
    @Test("The existing fixture manifest maps source-specific revision and query bounds into checked values")
    func manifestContract() throws {
        let decoded = try JSONDecoder().decode(MapFixtureManifest.self, from: Data(manifest.utf8))
        #expect(decoded.worldMetadata.sourceRevision == "world-commit")
        #expect(decoded.streetMetadata.sourceRevision == "street-snapshot")
        #expect(decoded.worldMetadata.attributionURL == nil)
        #expect(decoded.streetMetadata.attributionURL?.absoluteString == "https://example.test/credit")
        #expect(decoded.streetBounds.southwest.latitude == 1.278)
        #expect(decoded.streetBounds.southwest.longitude == 103.842)
        #expect(decoded.streetBounds.northeast.latitude == 1.300)
        #expect(decoded.streetBounds.northeast.longitude == 103.870)
    }

    @Test("Manifest decoding rejects malformed query boxes and missing required source context")
    func invalidManifest() {
        for bounds in ["[103.842,1.278,103.870]", "[103.842,1.278,103.870,1.300,2]",
                       "[103.870,1.278,103.842,1.300]", "[103.842,1.300,103.870,1.278]",
                       "[181,1.278,182,1.300]"] {
            let input = manifest.replacingOccurrences(of: "[103.842,1.278,103.870,1.300]", with: bounds)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(MapFixtureManifest.self, from: Data(input.utf8))
            }
        }
        for input in [
            manifest.replacingOccurrences(of: #""sourceCommit":"world-commit","#, with: ""),
            manifest.replacingOccurrences(of: #""sourceTimestamp":"street-snapshot","#, with: ""),
            manifest.replacingOccurrences(of: #""license":"Public domain","#, with: ""),
            manifest.replacingOccurrences(of: #""attribution":"World credit""#, with: #""attribution":" ""#),
            manifest.replacingOccurrences(of: "https://example.test/license", with: "file:///tmp/license"),
        ] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(MapFixtureManifest.self, from: Data(input.utf8))
            }
        }
    }

    private let manifest = #"{"sources":{"world":{"sourceCommit":"world-commit","attribution":"World credit","license":"Public domain","licenseURL":"https://example.test/license","sourceURL":"https://example.test/world"},"singapore":{"sourceTimestamp":"street-snapshot","attribution":"Street credit","attributionURL":"https://example.test/credit","license":"ODbL 1.0","licenseURL":"https://example.test/license","sourceURL":"https://example.test/street","queryBounds":[103.842,1.278,103.870,1.300]}}}"#
}
