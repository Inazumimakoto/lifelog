import Foundation

/// Photo matching keeps the existing byte/visual fingerprint semantics. The
/// expensive fallback is needed only when a location photo could actually match.
nonisolated struct PhotoIdentityIndex: Sendable {
    let assetIdentifiers: [String: [String]]
    let digests: [String: [String]]
    let visualDigests: [String: [String]]

    func matchingPath(assetIdentifier: String?, data: Data,
                      visualDigest: (Data) -> String? = PhotoStorage.visualDigest) -> String? {
        if let assetIdentifier, let path = assetIdentifiers[assetIdentifier]?.first { return path }
        if !digests.isEmpty {
            let digest = PhotoStorage.digestHex(for: data)
            if let path = digests[digest]?.first { return path }
        }
        guard !visualDigests.isEmpty, let digest = visualDigest(data) else { return nil }
        return visualDigests[digest]?.first
    }

    static func linkIdentity(assetIdentifier: String?,
                             fingerprint: @autoclosure () -> PhotoStorage.Fingerprint?) -> String? {
        if let assetIdentifier, !assetIdentifier.isEmpty { return "asset:" + assetIdentifier }
        guard let value = fingerprint() else { return nil }
        if let visualDigest = value.visualDigest, !visualDigest.isEmpty { return "visual:" + visualDigest }
        return "digest:" + value.digest
    }
}
