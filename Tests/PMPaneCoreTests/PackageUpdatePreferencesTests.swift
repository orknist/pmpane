import Foundation
import Testing
@testable import PMPaneCore

@Suite struct PackageUpdatePreferencesTests {
    private func makePackage(
        id: String = "brewFormula:wget",
        latest: String? = "2.0",
        outdated: Bool = true
    ) -> Package {
        Package(
            id: id,
            name: "wget",
            fullName: "wget",
            displayName: "wget",
            source: .brewFormula,
            installedVersion: "1.0",
            latestVersion: latest,
            isOutdated: outdated,
            updatesItself: false,
            greedyOnly: false,
            pinned: false,
            installedOnRequest: true,
            installedAsDependency: false,
            summary: "",
            trust: .official,
            versionIsLatest: !outdated
        )
    }

    @Test func ignoreSuppressesUpdatesAndClearsSkip() {
        var prefs = PackageUpdatePreferences()
        let pkg = makePackage()
        prefs.skipVersion(packageID: pkg.id, version: "2.0")
        #expect(prefs.isVersionSkipped(pkg))

        prefs.ignore(packageID: pkg.id)
        #expect(prefs.isIgnored(pkg))
        #expect(!prefs.isVersionSkipped(pkg))
        #expect(prefs.suppressesUpdates(for: pkg))
        #expect(prefs.skippedVersions[pkg.id] == nil)
    }

    @Test func skipOnlyMatchesCurrentLatest() {
        var prefs = PackageUpdatePreferences()
        let pkg = makePackage(latest: "2.0")
        prefs.skipVersion(packageID: pkg.id, version: "2.0")
        #expect(prefs.suppressesUpdates(for: pkg))

        let newer = makePackage(latest: "3.0")
        #expect(!prefs.isVersionSkipped(newer))
        #expect(!prefs.suppressesUpdates(for: newer))
    }

    @Test func clearMuteRemovesIgnoreAndSkip() {
        var prefs = PackageUpdatePreferences()
        let pkg = makePackage()
        prefs.ignore(packageID: pkg.id)
        prefs.clearMute(packageID: pkg.id)
        #expect(!prefs.suppressesUpdates(for: pkg))

        prefs.skipVersion(packageID: pkg.id, version: "2.0")
        prefs.clearMute(packageID: pkg.id)
        #expect(!prefs.suppressesUpdates(for: pkg))
    }

    @Test func pruneStaleSkipsKeepsActiveOnly() {
        var prefs = PackageUpdatePreferences()
        prefs.skippedVersions = [
            "brewFormula:wget": "2.0",
            "brewFormula:curl": "8.0",
            "npm:leftpad": "1.0",
        ]
        let packages = [
            makePackage(id: "brewFormula:wget", latest: "2.0"),
            makePackage(id: "brewFormula:curl", latest: "9.0"),
        ]
        prefs.pruneStaleSkips(using: packages)
        #expect(prefs.skippedVersions == ["brewFormula:wget": "2.0"])
    }

    @Test func roundTripPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMPanePrefs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var prefs = PackageUpdatePreferences()
        prefs.ignore(packageID: "brewCask:battery")
        prefs.skipVersion(packageID: "npm:leftpad", version: "1.2.3")
        try prefs.save(to: directory)

        let loaded = try PackageUpdatePreferences.load(from: directory)
        #expect(loaded == prefs)
    }
}
