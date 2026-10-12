import Foundation

/// App-level mute preferences for update nagging (independent of Homebrew pin).
///
/// - **Ignore**: suppress all update prompts for a package until cleared.
/// - **Skip version**: suppress only while `latestVersion` equals the stored value;
///   a newer release surfaces again automatically.
public struct PackageUpdatePreferences: Codable, Sendable, Equatable, Hashable {
    public var ignoredPackageIDs: Set<String>
    /// package id → skipped latest version string
    public var skippedVersions: [String: String]

    public static let storageFileName = "update-preferences.json"

    public init(
        ignoredPackageIDs: Set<String> = [],
        skippedVersions: [String: String] = [:]
    ) {
        self.ignoredPackageIDs = ignoredPackageIDs
        self.skippedVersions = skippedVersions
    }

    public func isIgnored(_ packageID: String) -> Bool {
        ignoredPackageIDs.contains(packageID)
    }

    public func isIgnored(_ package: Package) -> Bool {
        isIgnored(package.id)
    }

    /// True when this package’s current `latestVersion` was explicitly skipped.
    public func isVersionSkipped(_ package: Package) -> Bool {
        guard let latest = package.latestVersion, !latest.isEmpty else { return false }
        return skippedVersions[package.id] == latest
    }

    /// True when Updates / Outdated should hide this package.
    public func suppressesUpdates(for package: Package) -> Bool {
        isIgnored(package) || isVersionSkipped(package)
    }

    public mutating func ignore(packageID: String) {
        ignoredPackageIDs.insert(packageID)
        skippedVersions.removeValue(forKey: packageID)
    }

    public mutating func skipVersion(packageID: String, version: String) {
        guard !version.isEmpty else { return }
        ignoredPackageIDs.remove(packageID)
        skippedVersions[packageID] = version
    }

    public mutating func clearMute(packageID: String) {
        ignoredPackageIDs.remove(packageID)
        skippedVersions.removeValue(forKey: packageID)
    }

    /// Drop skip entries that no longer match any package’s current latest version.
    public mutating func pruneStaleSkips(using packages: [Package]) {
        let latestByID = Dictionary(uniqueKeysWithValues: packages.compactMap { pkg -> (String, String)? in
            guard let latest = pkg.latestVersion, !latest.isEmpty else { return nil }
            return (pkg.id, latest)
        })
        skippedVersions = skippedVersions.filter { id, version in
            latestByID[id] == version
        }
    }

    public static func load(from directory: URL) throws -> PackageUpdatePreferences {
        let url = directory.appendingPathComponent(storageFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PackageUpdatePreferences()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(PackageUpdatePreferences.self, from: data)
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.storageFileName)
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private static let decoder = JSONDecoder()
}
