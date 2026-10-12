import Foundation
import Testing
@testable import PMPaneCore

@Suite struct BrewCatalogFreshnessTests {
    @Test func lastUpdateDateReadsFetchHeadMtime() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmpane-brew-freshness-\(UUID().uuidString)", isDirectory: true)
        let git = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let fetchHead = git.appendingPathComponent("FETCH_HEAD")
        try Data("ref\n".utf8).write(to: fetchHead)

        let expected = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: expected],
            ofItemAtPath: fetchHead.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let actual = BrewCatalogFreshness.lastUpdateDate(repositoryPath: root.path)
        #expect(actual == expected)
    }

    @Test func lastUpdateDateMissingFetchHeadReturnsNil() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmpane-brew-freshness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(BrewCatalogFreshness.lastUpdateDate(repositoryPath: root.path) == nil)
    }

    @Test func repositoryPathFromBrewExecutable() {
        let path = BrewCatalogFreshness.repositoryPath(fromBrewExecutable: "/opt/homebrew/bin/brew")
        #expect(path == "/opt/homebrew")
    }

    @Test func updatedLabelUsesCoarseUnits() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            BrewCatalogFreshness.updatedLabel(
                for: now.addingTimeInterval(-3),
                relativeTo: now
            ) == "Updated just now"
        )
        #expect(
            BrewCatalogFreshness.updatedLabel(
                for: now.addingTimeInterval(-90),
                relativeTo: now
            ) == "Updated 1m ago"
        )
        #expect(
            BrewCatalogFreshness.updatedLabel(
                for: now.addingTimeInterval(-7200),
                relativeTo: now
            ) == "Updated 2h ago"
        )
        #expect(
            BrewCatalogFreshness.updatedLabel(
                for: now.addingTimeInterval(-172_800),
                relativeTo: now
            ) == "Updated 2d ago"
        )
    }
}
