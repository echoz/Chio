import Foundation

/// Required credit and provenance belong to the source, independently of its geometry.
struct MapSourceMetadata {
    let attribution: String
    /// Absence means the source specifies no separate attribution link.
    let attributionURL: URL?
    let license: String
    let licenseURL: URL
    let sourceURL: URL
    /// The source's pinned version, commit or snapshot timestamp.
    let sourceRevision: String

    init(attribution: String, attributionURL: URL? = nil, license: String,
         licenseURL: URL, sourceURL: URL, sourceRevision: String) throws {
        for text in [attribution, license, sourceRevision] {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= 1_024,
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw ValidationError.invalidText }
        }
        for url in [licenseURL, sourceURL] + [attributionURL].compactMap({ $0 }) {
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  !(url.host ?? "").isEmpty, url.user == nil, url.password == nil
            else { throw ValidationError.invalidURL }
        }
        self.attribution = attribution
        self.attributionURL = attributionURL
        self.license = license
        self.licenseURL = licenseURL
        self.sourceURL = sourceURL
        self.sourceRevision = sourceRevision
    }

    enum ValidationError: Error, Equatable, Sendable {
        case invalidText, invalidURL
    }
}

extension MapSourceMetadata: Hashable {}
extension MapSourceMetadata: Sendable {}
extension MapSourceMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case attribution, attributionURL, license, licenseURL, sourceURL, sourceRevision
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(attribution: values.decode(String.self, forKey: .attribution),
                      attributionURL: values.decodeIfPresent(URL.self, forKey: .attributionURL),
                      license: values.decode(String.self, forKey: .license),
                      licenseURL: values.decode(URL.self, forKey: .licenseURL),
                      sourceURL: values.decode(URL.self, forKey: .sourceURL),
                      sourceRevision: values.decode(String.self, forKey: .sourceRevision))
    }
}
