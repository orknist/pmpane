import Foundation

public enum PipParser {
    public static func packages(listJSON: Data, outdatedJSON: Data) throws -> [Package] {
        let decoder = JSONDecoder()
        let installed = try decoder.decode([PipListEntry].self, from: listJSON)
        let outdatedList = try decoder.decode([PipOutdatedEntry].self, from: outdatedJSON)
        let outdatedByName = Dictionary(uniqueKeysWithValues: outdatedList.map { ($0.name, $0) })

        return installed.map { entry in
            let outdated = outdatedByName[entry.name]
            let isOutdated = outdated != nil
            return Package(
                id: "pip:\(entry.name)",
                name: entry.name,
                fullName: entry.name,
                displayName: entry.name,
                source: .pip,
                installedVersion: entry.version,
                latestVersion: outdated?.latest_version,
                isOutdated: isOutdated,
                updatesItself: false,
                greedyOnly: false,
                pinned: false,
                installedOnRequest: true,
                installedAsDependency: false,
                summary: "",
                homepage: nil,
                tap: nil,
                trust: .notApplicable,
                versionIsLatest: false
            )
        }
        .sorted { $0.name < $1.name }
    }
}

private struct PipListEntry: Decodable {
    var name: String
    var version: String
}

private struct PipOutdatedEntry: Decodable {
    var name: String
    var version: String
    var latest_version: String
}
